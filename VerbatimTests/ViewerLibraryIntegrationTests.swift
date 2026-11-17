import Foundation
import Testing

@testable import Verbatim

/// What the open recording shows and offers, following a real Library in a temporary folder.
@MainActor
struct ViewerLibraryIntegrationTests: ViewerPlaybackTesting {
    let environment: LibraryTestEnvironment
    let repository: SQLiteRecordingRepository
    let library: LibraryService
    let playback = FakePlaybackService()
    let viewModel: ViewerViewModel

    init() throws {
        environment = try LibraryTestEnvironment()
        repository = environment.makeRepository()
        library = environment.makeService(repository: repository)
        viewModel = ViewerViewModel(library: library, playback: playback)
    }

    // MARK: - Following the Library

    @Test func aRenameInTheLibraryUpdatesTheOpenRecording() async throws {
        let recording = try await opened("Old")

        try await library.rename(recording.id, to: "New")
        await viewModel.refreshMetadata()

        #expect(viewModel.title == "New")
        #expect(viewModel.recording?.item.title == "New")
        #expect(viewModel.playbackState == .ready)
    }

    @Test func removingTheOpenRecordingEndsPlayback() async throws {
        let recording = try await opened()
        viewModel.togglePlayback()

        _ = try await library.removeFromLibrary(recording.id)
        await viewModel.refreshMetadata()

        #expect(viewModel.playbackState == .failed(.recordingNotFound))
        #expect(viewModel.recording == nil)
        #expect(playback.calls.last == .unload)
    }

    @Test func committingATitleRenamesTheEntry() async throws {
        let recording = try await opened("Old")

        viewModel.title = "New"
        viewModel.commitTitle()
        await viewModel.waitUntilSettled()

        let updated = try await repository.fetch(id: recording.id)
        #expect(updated?.recording.title == "New")
    }

    @Test func aRefusedTitleGoesBack() async throws {
        _ = try await opened("Old")

        viewModel.title = "   "
        viewModel.commitTitle()
        await viewModel.waitUntilSettled()

        #expect(viewModel.title == "Old")
        #expect(viewModel.actionIssue != nil)
    }

    // MARK: - Transcript panel

    @Test func realRecordingsHaveNoTranscriptAndNoInventedLines() async throws {
        _ = try await opened()

        #expect(viewModel.recording?.transcriptState == .unavailable)
        #expect(viewModel.lines.isEmpty)
        #expect(viewModel.activeLineIndex == nil)
        #expect(viewModel.matchingLineIndices.isEmpty)
        #expect(!viewModel.canShowTranscriptInFinder)

        viewModel.startProcessing()
        #expect(viewModel.recording?.transcriptState == .unavailable)
    }

    // MARK: - Finder

    @Test func finderActionsUseTheLibrarysFileHandling() async throws {
        let recording = try await opened()
        let media = recording.media.url

        viewModel.showInFinder()
        await viewModel.waitUntilSettled()
        viewModel.openFolder()
        await viewModel.waitUntilSettled()

        #expect(await environment.finder.state.revealed == [media])
        #expect(await environment.finder.state.opened == [media.deletingLastPathComponent()])
    }

    @Test func aTranscriptFileOnDiskCanBeShownInFinder() async throws {
        let recording = try await stored()
        let transcript = recording.media.url.deletingLastPathComponent().appending(path: "transcript.txt")
        try Data("text".utf8).write(to: transcript)

        viewModel.open(recordingID: recording.id)
        await viewModel.waitUntilSettled()
        #expect(viewModel.canShowTranscriptInFinder)

        viewModel.showTranscriptInFinder()
        await viewModel.waitUntilSettled()

        #expect(await environment.finder.state.revealed.map(\.lastPathComponent) == ["transcript.txt"])
        #expect(viewModel.actionIssue == nil)
    }

    @Test func showingAMissingFileInFinderExplainsWhy() async throws {
        let recording = try await opened()
        try FileManager.default.removeItem(at: recording.media.url)

        viewModel.showInFinder()
        await viewModel.waitUntilSettled()

        #expect(viewModel.actionIssue != nil)
        #expect(viewModel.playbackState == .ready)
    }

    // MARK: - Design scenarios

    @Test func aScenarioEndsAnyRealSessionAndLiveReturnsToNothing() async throws {
        _ = try await opened()

        viewModel.apply(.video)
        #expect(viewModel.isPreviewing)
        #expect(playback.calls.last == .unload)
        #expect(viewModel.openMedia == nil)

        viewModel.endPreview()
        #expect(!viewModel.isPreviewing)
        #expect(viewModel.playbackState == .idle)
        #expect(viewModel.recording == nil)
    }
}
