import Foundation
import Testing

@testable import Recorder

/// The Library window's model against a real database and real files.
@MainActor
struct LibraryViewModelLiveTests {
    private let environment: LibraryTestEnvironment
    private let repository: SQLiteRecordingRepository
    private let service: LibraryService
    private let viewModel: LibraryViewModel

    init() throws {
        environment = try LibraryTestEnvironment()
        repository = environment.makeRepository()
        service = environment.makeService(repository: repository)
        viewModel = LibraryViewModel(service: service)
    }

    @discardableResult
    private func stored(
        _ title: String,
        createdAt: Date = .now,
        duration: TimeInterval = 60,
        mode: CaptureMode = .screen
    ) async throws -> LibraryRecording {
        let recording = try environment.makeRecording(
            title: title,
            createdAt: createdAt,
            duration: duration,
            mode: mode
        )
        try await repository.insert(recording)
        return recording
    }

    private func settle() async {
        await viewModel.waitUntilSettled()
        await viewModel.reload()
    }

    @Test func anEmptyLibraryShowsTheEmptyStateAndNoSamples() async {
        #expect(viewModel.content == .loading)

        await viewModel.reload()

        #expect(viewModel.content == .empty)
        #expect(viewModel.items.isEmpty)
        #expect(!viewModel.isPreviewing)
    }

    @Test func showsWhatIsStored() async throws {
        let recording = try await stored("Architecture Review", duration: 90, mode: .window)

        await viewModel.reload()

        let item = try #require(viewModel.items.first)
        #expect(viewModel.content == .recordings)
        #expect(item.id == recording.id)
        #expect(item.title == "Architecture Review")
        #expect(item.duration == 90)
        #expect(item.sizeBytes == 2_048)
        #expect(item.kind == .window)
        #expect(item.status == .recorded)
        #expect(item.fileNames == ["recording.mov", "recording.json"])
        #expect(item.location?.folderPath == nil)
        #expect(item.location?.trashesFolder == true)
        #expect(viewModel.storage.folderPath == "~/Verbatim")
        #expect(viewModel.storage.usedBytes == 2_048)
    }

    @Test func offersNoProcessingItCannotDo() async throws {
        try await stored("Demo")

        await viewModel.reload()

        let item = try #require(viewModel.items.first)
        #expect(!item.canStartProcessing)
        #expect(item.statusActionTitle == nil)
        #expect(viewModel.count(for: .processing) == 0)
        viewModel.select(filter: .processing)
        #expect(!viewModel.showsProcessingNote)
    }

    @Test func aFinishedRecordingChangesTheReloadKey() async throws {
        await viewModel.reload()
        let key = viewModel.reloadKey
        let destination = try environment.makeRecordingFolder()
        let metadata = RecordingMetadata(
            recording: Recording(id: UUID(), createdAt: .now, validatedMediaDuration: 3, processingStatus: .recorded),
            mediaFileName: RecordingFileLayout.mediaFileName,
            captureMode: .screen,
            sourceName: "Display",
            hasVideo: true,
            audioSources: [],
            fileSizeBytes: 2_048,
            completion: .complete,
            transcriptionRequested: false
        )

        try await service.addFinishedRecording(metadata, destination: destination)

        #expect(viewModel.reloadKey != key)
        await viewModel.reload()
        #expect(viewModel.items.count == 1)
    }

    @Test func countsSectionsFromTheDatabase() async throws {
        try await stored("Screen", mode: .screen)
        try await stored("Window", mode: .window)
        try await stored("Audio", mode: .audioOnly)
        try await stored("Old", createdAt: Date(timeIntervalSince1970: 1_000), mode: .screen)

        await viewModel.reload()

        #expect(viewModel.count(for: .all) == 4)
        #expect(viewModel.count(for: .recent) == 3)
        #expect(viewModel.count(for: .screen) == 3)
        #expect(viewModel.count(for: .audio) == 1)
    }

    @Test func sectionsAndSortingComeBackFromTheDatabase() async throws {
        try await stored("Screen", createdAt: Date(timeIntervalSince1970: 2_000), duration: 5)
        try await stored("Audio", createdAt: Date(timeIntervalSince1970: 1_000), duration: 9, mode: .audioOnly)

        viewModel.select(sortOrder: .duration)
        await viewModel.reload()
        #expect(viewModel.visibleItems.map(\.title) == ["Audio", "Screen"])

        viewModel.select(filter: .audio)
        await viewModel.reload()
        #expect(viewModel.visibleItems.map(\.title) == ["Audio"])
    }

    @Test func searchFiltersTheListAndSaysWhenNothingMatches() async throws {
        try await stored("Weekly Sync")
        try await stored("Design Critique")

        viewModel.updateSearchText("week")
        await viewModel.reload()
        #expect(viewModel.content == .recordings)
        #expect(viewModel.items.map(\.title) == ["Weekly Sync"])

        viewModel.updateSearchText("nothing like this")
        await viewModel.reload()
        #expect(viewModel.content == .noResults)
    }

    @Test func renamesFromTheSheet() async throws {
        let recording = try await stored("Old")
        await viewModel.reload()
        viewModel.requestRename(recording.id)
        #expect(viewModel.pendingRename?.id == recording.id)

        viewModel.rename(recording.id, to: "New")
        await settle()

        #expect(viewModel.pendingRename == nil)
        #expect(viewModel.items.first?.title == "New")
    }

    @Test func aBlankRenameShowsAnIssueAndChangesNothing() async throws {
        let recording = try await stored("Old")
        await viewModel.reload()

        viewModel.rename(recording.id, to: "  ")
        await settle()

        #expect(viewModel.issue != nil)
        #expect(viewModel.items.first?.title == "Old")
    }

    @Test func removingKeepsTheFileAndOffersUndo() async throws {
        let recording = try await stored("Demo")
        await viewModel.reload()
        viewModel.select(recording.id)

        viewModel.removeFromLibrary(recording.id)
        await settle()

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.lastRemoval?.recording?.id == recording.id)
        #expect(FileManager.default.fileExists(atPath: recording.media.url.path(percentEncoded: false)))

        viewModel.undoRemoval()
        await settle()

        #expect(viewModel.items.map(\.id) == [recording.id])
        #expect(viewModel.selectedItemID == recording.id)
        #expect(viewModel.lastRemoval == nil)
    }

    @Test func deletingMovesToTheTrashAndSelectsTheNeighbor() async throws {
        let older = try await stored("Older", createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = try await stored("Newer", createdAt: Date(timeIntervalSince1970: 2_000))
        await viewModel.reload()
        viewModel.select(newer.id)
        viewModel.requestDeletion(of: newer.id)
        #expect(viewModel.pendingDeletion?.id == newer.id)

        viewModel.moveToTrash(newer.id)
        await settle()

        #expect(viewModel.pendingDeletion == nil)
        #expect(viewModel.items.map(\.id) == [older.id])
        #expect(viewModel.selectedItemID == older.id)
        #expect(viewModel.lastRemoval == nil)
        #expect(try environment.trashedItemNames().count == 1)
    }

    @Test func aFailedDeletionKeepsTheRecordingAndShowsAnIssue() async throws {
        let failing = environment.makeService(
            repository: repository,
            fileStore: TrashFailingFileStore(base: environment.makeFileStore())
        )
        let viewModel = LibraryViewModel(service: failing)
        let recording = try await stored("Demo")
        await viewModel.reload()

        viewModel.moveToTrash(recording.id)
        await viewModel.waitUntilSettled()
        await viewModel.reload()

        #expect(viewModel.items.map(\.id) == [recording.id])
        #expect(viewModel.issue != nil)
    }

    @Test func aMissingFileShowsAsMissingAndCanOnlyBeLocatedOrRemoved() async throws {
        let recording = try await stored("Demo")
        try FileManager.default.removeItem(at: recording.media.url)

        await viewModel.reload()

        let item = try #require(viewModel.items.first)
        #expect(item.status == .missing)
        #expect(item.location?.unavailability == .missing)
        #expect(item.statusActionTitle != nil)
        #expect(!LibraryContextMenu.Command.openRecording.isEnabled(for: item))
        #expect(!LibraryContextMenu.Command.showInFinder.isEnabled(for: item))
        #expect(!LibraryContextMenu.Command.deleteRecording.isEnabled(for: item))
        #expect(LibraryContextMenu.Command.locateFile.isEnabled(for: item))
        #expect(LibraryContextMenu.Command.removeFromLibrary.isEnabled(for: item))

        viewModel.requestDeletion(of: item.id)
        #expect(viewModel.pendingDeletion == nil)
    }

    @Test func locatingFromTheOpenPanelRestoresTheRecording() async throws {
        let recording = try await stored("Demo")
        try FileManager.default.removeItem(at: recording.media.url)
        await viewModel.reload()
        let replacement = try await environment.writePlayableMedia(hasVideo: true)

        viewModel.requestLocate(recording.id)
        #expect(viewModel.locatingItemID == recording.id)
        viewModel.finishLocating(.success(replacement))
        await settle()

        #expect(viewModel.locatingItemID == nil)
        #expect(viewModel.items.count == 1)
        #expect(viewModel.items.first?.status == .recorded)
        #expect(viewModel.items.first?.id == recording.id)
    }

    @Test func aDatabaseThatCannotOpenShowsAFailureAndRecovers() async throws {
        try FileManager.default.createDirectory(
            at: environment.databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: 8_192).write(to: environment.databaseURL)

        await viewModel.reload()

        guard case .failed = viewModel.content else {
            Issue.record("Expected a failure, got \(viewModel.content)")
            return
        }

        try FileManager.default.removeItem(at: environment.databaseURL)
        await viewModel.reload()

        #expect(viewModel.content == .empty)
    }

    @Test func designScenariosNeverTouchTheLibrary() async throws {
        let recording = try await stored("Real")
        await viewModel.reload()

        viewModel.apply(.list)
        #expect(viewModel.isPreviewing)
        #expect(viewModel.items.contains { $0.title == "Architecture Review" })
        let sample = try #require(viewModel.items.first)
        viewModel.moveToTrash(sample.id)
        viewModel.showInFinder(sample.id)
        await viewModel.waitUntilSettled()
        #expect(try environment.trashedItemNames().isEmpty)
        #expect(await environment.finder.state.revealed.isEmpty)

        viewModel.endPreview()
        await viewModel.reload()
        #expect(viewModel.items.map(\.id) == [recording.id])
    }
}
