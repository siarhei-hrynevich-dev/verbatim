import Foundation
import Observation

/// Presentation state of the Library window.
///
/// This is a layout-only implementation: recordings, processing progress and search results come from fixed
/// sample data, and removing, deleting or retrying only changes local state. No storage, Finder, transcription
/// or search service is involved yet.
@MainActor
@Observable
final class LibraryViewModel {
    enum Content: Equatable {
        case recordings
        case searchResults(LibrarySearchResults)
        /// The library has no recordings at all.
        case empty
    }

    /// A recording removed from the Library that can still be restored with Undo.
    struct Removal: Equatable {
        let item: LibraryItem
        let index: Int
    }

    let storage: LibraryStorage

    private(set) var items: [LibraryItem] = []
    private(set) var filter: LibraryFilter = .all
    private(set) var sortOrder: LibrarySortOrder = .newestFirst
    private(set) var searchText = ""
    private(set) var selectedItemID: LibraryItem.ID?
    private(set) var contextMenuItemID: LibraryItem.ID?
    private(set) var pendingDeletionID: LibraryItem.ID?
    private(set) var lastRemoval: Removal?

    private let previewData: LibraryPreviewData
    private let now: Date
    private let calendar: Calendar

    init(
        previewData: LibraryPreviewData = .sample(),
        scenario: LibraryPreviewScenario = .list,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        self.previewData = previewData
        self.now = now
        self.calendar = calendar
        storage = previewData.storage
        apply(scenario)
    }

    // MARK: - Derived state

    /// Recordings in the selected sidebar section, in the chosen order.
    var visibleItems: [LibraryItem] {
        let filtered = items.filter { filter.includes($0, now: now, calendar: calendar) }
        return filtered.sorted { first, second in
            switch sortOrder {
            case .newestFirst: first.recordedAt > second.recordedAt
            case .oldestFirst: first.recordedAt < second.recordedAt
            }
        }
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var content: Content {
        if isSearching {
            return .searchResults(
                SimulatedLibrarySearch.results(for: searchText, in: items, transcript: previewData.transcript)
            )
        }
        return items.isEmpty ? .empty : .recordings
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

    /// The path bar describes the selected recording's folder while the list is shown.
    var pathBarItem: LibraryItem? {
        isSearching ? nil : selectedItem
    }

    var showsProcessingNote: Bool {
        filter == .processing && !isSearching
    }

    func count(for filter: LibraryFilter) -> Int {
        items.count { filter.includes($0, now: now, calendar: calendar) }
    }

    /// How many recordings are being transcribed and indexed.
    var processingCounts: (transcribing: Int, indexing: Int) {
        var transcribing = 0
        var indexing = 0
        for item in items {
            switch item.status {
            case .transcribing: transcribing += 1
            case .indexing: indexing += 1
            case .ready, .recorded, .failed, .missing: break
            }
        }
        return (transcribing, indexing)
    }

    // MARK: - Browsing

    /// Shows a sidebar section. Like choosing a section in Finder, this ends a search.
    func select(filter: LibraryFilter) {
        self.filter = filter
        searchText = ""
        contextMenuItemID = nil
        if let selectedItemID, !visibleItems.contains(where: { $0.id == selectedItemID }) {
            self.selectedItemID = nil
        }
    }

    func updateSearchText(_ text: String) {
        searchText = text
        contextMenuItemID = nil
    }

    func toggleSortOrder() {
        sortOrder = sortOrder == .newestFirst ? .oldestFirst : .newestFirst
    }

    func select(_ id: LibraryItem.ID?) {
        selectedItemID = id
        contextMenuItemID = nil
    }

    /// Moves the selection through the visible list, as the arrow keys do. Without a selection, moving down
    /// selects the first recording and moving up the last.
    func moveSelection(by offset: Int) {
        let visible = visibleItems
        guard !visible.isEmpty else {
            return
        }
        guard let selectedItemID, let index = visible.firstIndex(where: { $0.id == selectedItemID }) else {
            select(offset >= 0 ? visible.first?.id : visible.last?.id)
            return
        }
        let newIndex = min(max(index + offset, 0), visible.count - 1)
        select(visible[newIndex].id)
    }

    // MARK: - Context menu and deletion

    func showContextMenu(for id: LibraryItem.ID) {
        selectedItemID = id
        contextMenuItemID = id
    }

    func dismissContextMenu() {
        contextMenuItemID = nil
    }

    func requestDeletion(of id: LibraryItem.ID) {
        contextMenuItemID = nil
        pendingDeletionID = id
    }

    func cancelDeletion() {
        pendingDeletionID = nil
    }

    /// Removes the recording from the Library and offers Undo. Its files stay in Finder.
    func removeFromLibrary(_ id: LibraryItem.ID) {
        remove(id, offeringUndo: true)
    }

    /// Simulates moving the recording folder to the Trash; it only leaves the list.
    func moveToTrash(_ id: LibraryItem.ID) {
        remove(id, offeringUndo: false)
    }

    func undoRemoval() {
        guard let lastRemoval else {
            return
        }
        items.insert(lastRemoval.item, at: min(lastRemoval.index, items.count))
        selectedItemID = lastRemoval.item.id
        self.lastRemoval = nil
    }

    // MARK: - Processing

    /// Simulates starting transcription for a recording without a transcript or with failed processing.
    func startProcessing(_ id: LibraryItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].canStartProcessing else {
            return
        }
        items[index].status = .transcribing(progress: Self.initialProgress)
        contextMenuItemID = nil
    }

    // MARK: - Preview scenarios

    func apply(_ scenario: LibraryPreviewScenario) {
        items = scenario == .empty ? [] : previewData.items
        filter = scenario == .processing ? .processing : .all
        sortOrder = .newestFirst
        searchText = scenario == .search ? LibraryPreviewScenario.sampleSearchQuery : ""
        lastRemoval = nil
        selectedItemID = sampleItemID(at: Self.selectedSampleIndex(for: scenario))
        contextMenuItemID = scenario == .context ? selectedItemID : nil
        pendingDeletionID = scenario == .confirm ? selectedItemID : nil
    }

    // MARK: - Private

    private func item(withID id: LibraryItem.ID?) -> LibraryItem? {
        guard let id else {
            return nil
        }
        return items.first { $0.id == id }
    }

    private func remove(_ id: LibraryItem.ID, offeringUndo: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        let nextSelection = selectedItemID == id ? neighbor(ofVisibleItem: id) : selectedItemID
        let removed = items.remove(at: index)
        lastRemoval = offeringUndo ? Removal(item: removed, index: index) : nil
        contextMenuItemID = nil
        pendingDeletionID = nil
        selectedItemID = nextSelection
    }

    /// The recording that takes a removed one's place in the visible list, so keyboard work can continue.
    private func neighbor(ofVisibleItem id: LibraryItem.ID) -> LibraryItem.ID? {
        let visible = visibleItems
        guard let index = visible.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        if index + 1 < visible.count {
            return visible[index + 1].id
        }
        return index > 0 ? visible[index - 1].id : nil
    }

    private func sampleItemID(at index: Int?) -> LibraryItem.ID? {
        guard let index, items.indices.contains(index) else {
            return nil
        }
        return items[index].id
    }

    /// The design selects Architecture Review, Weekly Team Sync while processing, and Design Critique in the
    /// delete confirmation.
    private static func selectedSampleIndex(for scenario: LibraryPreviewScenario) -> Int? {
        switch scenario {
        case .list, .search, .context: 0
        case .processing: 1
        case .confirm: 5
        case .empty: nil
        }
    }

    /// Restarted processing shows a sliver of progress right away, as in the design prototype.
    private static let initialProgress = 0.02
}
