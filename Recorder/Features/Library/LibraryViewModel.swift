import Foundation
import Observation
import os

/// Presentation state of the Library window.
///
/// Live, it shows what `LibraryService` holds: the database does the filtering, sorting and searching, and `reload()`
/// runs whenever `reloadKey` changes. For design review it can instead show a `LibraryPreviewScenario`, with fixed
/// sample recordings and simulated actions that touch nothing on disk.
@MainActor
@Observable
final class LibraryViewModel {
    enum Content: Equatable {
        case loading
        case failed(LibraryIssue)
        case recordings
        case searchResults(LibrarySearchResults)
        /// A search found nothing, among recordings that exist.
        case noResults
        /// The library has no recordings at all.
        case empty
    }

    /// A recording removed from the Library that can still be restored with Undo.
    struct Removal: Equatable {
        let item: LibraryItem
        let index: Int
        /// The stored entry to put back; sample recordings have none.
        var recording: LibraryRecording?
    }

    /// Everything that requires asking the database again. The window reloads when this changes.
    struct ReloadKey: Equatable {
        let revision: Int
        let processingRevision: Int
        let refreshCount: Int
        let isPreviewing: Bool
        let filter: LibraryFilter
        let sortOrder: RecordingSortOrder
        let searchText: String
    }

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(LibraryIssue)
    }

    // Only this type and its extensions in `LibraryViewModel+*.swift` write these; Swift has no narrower access level
    // that spans files. Views read them and call the actions.
    var storage: LibraryStorage
    var items: [LibraryItem] = []
    var filter: LibraryFilter = .all
    var sortOrder: RecordingSortOrder = .newestFirst
    var searchText = ""
    var selectedItemID: LibraryItem.ID?
    var contextMenuItemID: LibraryItem.ID?
    var pendingDeletionID: LibraryItem.ID?
    var renamingItemID: LibraryItem.ID?
    var locatingItemID: LibraryItem.ID?
    var lastRemoval: Removal?
    var issue: LibraryIssue?
    /// Whether this shows a design scenario instead of the real library.
    var isPreviewing: Bool

    var loadState = LoadState.loading
    var counts: [LibraryFilter: Int] = [:]
    var recordings: [UUID: LibraryRecording] = [:]
    var lastInspections: [UUID: RecordingFileInspection] = [:]
    var refreshCount = 0

    /// Runs library operations one at a time, in request order, for as long as the app does.
    @ObservationIgnored private var lastOperation: Task<Void, Never>?

    @ObservationIgnored let service: LibraryService?
    /// Read for status and progress, which change while the window is open.
    @ObservationIgnored let processing: ProcessingCoordinator?
    let previewData: LibraryPreviewData
    private let fixedNow: Date?
    let calendar: Calendar

    /// The real library. A `previewScenario` starts on sample data instead, until `endPreview()`.
    init(
        service: LibraryService,
        processing: ProcessingCoordinator? = nil,
        previewScenario: LibraryPreviewScenario? = nil,
        calendar: Calendar = .current
    ) {
        self.service = service
        self.processing = processing
        previewData = .sample()
        fixedNow = nil
        self.calendar = calendar
        storage = LibraryStorage(folderPath: "", usedBytes: 0, freeBytes: 0)
        isPreviewing = false
        if let previewScenario {
            apply(previewScenario)
        }
    }

    /// Sample data only, for SwiftUI previews and tests of the design states.
    init(
        previewData: LibraryPreviewData = .sample(),
        scenario: LibraryPreviewScenario = .list,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        service = nil
        processing = nil
        self.previewData = previewData
        fixedNow = now
        self.calendar = calendar
        storage = previewData.storage
        isPreviewing = true
        apply(scenario)
    }

    // MARK: - Derived state

    var reloadKey: ReloadKey {
        ReloadKey(
            revision: service?.revision ?? 0,
            processingRevision: processing?.revision ?? 0,
            refreshCount: refreshCount,
            isPreviewing: isPreviewing,
            filter: filter,
            sortOrder: sortOrder,
            searchText: searchText
        )
    }

    /// Recordings in the selected sidebar section, in the chosen order. When live, the database has done both.
    var visibleItems: [LibraryItem] {
        guard isPreviewing else {
            return items.map(withMeasuredProgress)
        }
        let filtered = items.filter { filter.includes($0, now: now, calendar: calendar) }
        return filtered.sorted { first, second in
            switch sortOrder {
            case .newestFirst: first.recordedAt > second.recordedAt
            case .oldestFirst: first.recordedAt < second.recordedAt
            case .name: first.title.localizedStandardCompare(second.title) == .orderedAscending
            case .duration: first.duration > second.duration
            }
        }
    }

    var isSearching: Bool {
        !trimmedSearchText.isEmpty
    }

    var content: Content {
        if isPreviewing {
            return previewContent
        }
        switch loadState {
        case .loading:
            return .loading
        case .failed(let issue):
            return .failed(issue)
        case .loaded:
            if counts[.all, default: 0] == 0 {
                return .empty
            }
            return isSearching && items.isEmpty ? .noResults : .recordings
        }
    }

    var selectedItem: LibraryItem? {
        item(withID: selectedItemID)
    }

    var contextMenuItem: LibraryItem? {
        item(withID: contextMenuItemID)
    }

    var pendingDeletion: LibraryItem? {
        item(withID: pendingDeletionID)
    }

    var pendingRename: LibraryItem? {
        item(withID: renamingItemID)
    }

    /// The path bar describes the selected recording's folder while the list is shown.
    var pathBarItem: LibraryItem? {
        isPreviewing && isSearching ? nil : selectedItem
    }

    /// The note about pausing the queue belongs to the design: real jobs are stopped one at a time.
    var showsProcessingNote: Bool {
        isPreviewing && filter == .processing && !isSearching
    }

    func count(for filter: LibraryFilter) -> Int {
        guard isPreviewing else {
            return counts[filter, default: 0]
        }
        return items.count { filter.includes($0, now: now, calendar: calendar) }
    }

    /// How many recordings are being transcribed and indexed.
    var processingCounts: (transcribing: Int, indexing: Int) {
        var transcribing = 0
        var indexing = 0
        for item in items {
            switch item.status {
            case .transcribing: transcribing += 1
            case .indexing: indexing += 1
            case .ready, .pending, .recorded, .failed, .missing: break
            }
        }
        return (transcribing, indexing)
    }

    /// Waits for the requested operations to finish.
    func waitUntilSettled() async {
        await lastOperation?.value
    }

    /// Runs an operation after those already requested, presenting its failure. Does nothing in a design scenario.
    func perform(_ operation: @escaping @MainActor (LibraryService) async throws -> Void) {
        guard let service, !isPreviewing else {
            return
        }
        let previous = lastOperation
        lastOperation = Task { [weak self] in
            await previous?.value
            do {
                try await operation(service)
            } catch {
                Self.logger.error("A Library action failed: \(String(describing: error))")
                self?.issue = LibraryIssue(error)
            }
        }
    }

    // MARK: - Private

    var now: Date {
        fixedNow ?? .now
    }

    var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Progress changes too often to go through the database, so it joins the stored status here.
    private func withMeasuredProgress(_ item: LibraryItem) -> LibraryItem {
        guard case .transcribing = item.status, let fraction = processing?.progress[item.id] else {
            return item
        }
        var measured = item
        measured.status = .transcribing(progress: fraction)
        return measured
    }

    private var previewContent: Content {
        if isSearching {
            return .searchResults(
                SimulatedLibrarySearch.results(for: searchText, in: items, transcript: previewData.transcript)
            )
        }
        return items.isEmpty ? .empty : .recordings
    }

    func item(withID id: LibraryItem.ID?) -> LibraryItem? {
        guard let id else {
            return nil
        }
        return items.first { $0.id == id }
    }

    func selectNeighbor(of id: LibraryItem.ID) {
        contextMenuItemID = nil
        pendingDeletionID = nil
        if selectedItemID == id {
            selectedItemID = neighbor(ofVisibleItem: id)
        }
    }

    /// The recording that takes a removed one's place in the visible list, so keyboard work can continue.
    func neighbor(ofVisibleItem id: LibraryItem.ID) -> LibraryItem.ID? {
        let visible = visibleItems
        guard let index = visible.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        if index + 1 < visible.count {
            return visible[index + 1].id
        }
        return index > 0 ? visible[index - 1].id : nil
    }

    static let logger = Logger(subsystem: "dev.local.Recorder", category: "Library")
}
