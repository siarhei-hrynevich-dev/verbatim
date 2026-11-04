import Foundation
import Testing

@testable import Recorder

/// Opening, failing, switching and closing, on a real Library in a temporary folder with the player replaced.
@MainActor
struct ViewerPlaybackTests: ViewerPlaybackTesting {
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

    // MARK: - Loading

    @Test func startsWithNothingOpen() {
        #expect(viewModel.playbackState == .idle)
        #expect(viewModel.recording == nil)
        #expect(!viewModel.canControlPlayback)
    }

    @Test func openingLoadsMetadataAndTheMediaFile() async throws {
        let recording = try await stored("Planning", mode: .window)

        viewModel.open(recordingID: recording.id)
        #expect(viewModel.playbackState == .loading)
        await viewModel.waitUntilSettled()

        #expect(viewModel.playbackState == .ready)
        #expect(viewModel.title == "Planning")
        #expect(viewModel.recording?.item.id == recording.id)
        #expect(viewModel.recording?.item.kind == .window)
        #expect(viewModel.recording?.item.recordedAt == recording.recording.createdAt)
        #expect(viewModel.recording?.item.sizeBytes == recording.fileSizeBytes)
        #expect(playback.calls.contains(.load(recording.media.url)))
    }

    @Test func aRecordingStaysPausedUntilAskedToPlay() async throws {
        _ = try await opened()

        #expect(!playback.calls.contains(.play))
        #expect(!viewModel.isPlaying)
    }

    @Test func aTimestampIsWhereItStarts() async throws {
        let recording = try await stored()

        viewModel.open(recordingID: recording.id, at: 42)
        await viewModel.waitUntilSettled()

        #expect(playback.seeks == [.seek(42, .exact)])
        #expect(viewModel.position == 42)
    }

    @Test func playbackUsesTheMediasRealDuration() async throws {
        playback.info = PlaybackMediaInfo(duration: 45, hasVideo: true, audioTrackCount: 1)
        let recording = try await stored(duration: 60)

        viewModel.open(recordingID: recording.id)
        await viewModel.waitUntilSettled()

        #expect(viewModel.duration == 45)
        viewModel.seek(to: 50)
        #expect(viewModel.position == 45)
        let stillStored = try await repository.fetch(id: recording.id)
        #expect(stillStored?.recording.duration == 60)
    }

    @Test func theFileDecidesBetweenPictureAndAudio() async throws {
        playback.info = PlaybackMediaInfo(duration: 60, hasVideo: false, audioTrackCount: 2)
        let recording = try await stored(mode: .audioOnly)

        viewModel.open(recordingID: recording.id)
        #expect(viewModel.playbackState == .loading)
        await viewModel.waitUntilSettled()

        #expect(!viewModel.showsVideo)
        #expect(viewModel.mediaInfo?.audioTrackCount == 2)
        #expect(viewModel.playbackState == .ready)
    }

    // MARK: - Errors

    @Test func aMissingFileKeepsTheMetadataAndOffersToLocateIt() async throws {
        let recording = try await stored("Gone")
        try FileManager.default.removeItem(at: recording.media.url)

        viewModel.open(recordingID: recording.id)
        await viewModel.waitUntilSettled()

        #expect(viewModel.playbackState == .failed(.mediaUnavailable(.missing)))
        #expect(viewModel.title == "Gone")
        #expect(viewModel.recording?.item.isMissing == true)
        #expect(viewModel.playbackIssue?.recoveries.first == .locateFile)
        #expect(!playback.calls.contains(.load(recording.media.url)))
    }

    @Test func anUnknownRecordingFails() async {
        viewModel.open(recordingID: UUID())
        await viewModel.waitUntilSettled()

        #expect(viewModel.playbackState == .failed(.recordingNotFound))
        #expect(viewModel.recording == nil)
    }

    @Test(arguments: [PlaybackFailure.unsupportedFormat, .corruptedMedia, .mediaUnavailable(.accessDenied)])
    func playerFailuresReachTheUserAndReleaseTheSession(failure: PlaybackFailure) async throws {
        playback.loadFailure = failure

        _ = try await opened()

        #expect(viewModel.playbackState == .failed(failure))
        #expect(viewModel.playbackIssue != nil)
        #expect(viewModel.openMedia == nil)
        #expect(viewModel.mediaInfo == nil)
        #expect(playback.calls.last == .unload)
    }

    @Test func retryingOpensTheRecordingAgain() async throws {
        playback.loadFailure = .corruptedMedia
        _ = try await opened()

        playback.loadFailure = nil
        viewModel.retry()
        await viewModel.waitUntilSettled()

        #expect(viewModel.playbackState == .ready)
    }

    @Test func aFailureDuringPlaybackStopsItAndCanBeRetried() async throws {
        _ = try await opened()
        viewModel.togglePlayback()

        playback.emit(.failed(.playbackFailed(detail: "decoder")))

        #expect(viewModel.playbackState == .failed(.playbackFailed(detail: "decoder")))
        #expect(!viewModel.canControlPlayback)
        #expect(viewModel.playbackIssue?.recoveries.contains(.retry) == true)
    }

    @Test func aFailedSeekReportsAndReturnsToTheRealPosition() async throws {
        _ = try await opened()
        playback.currentTime = 12
        playback.seekFailure = .seekFailed

        viewModel.seek(to: 30)
        #expect(viewModel.position == 30)
        await viewModel.waitUntilSettled()

        #expect(viewModel.position == 12)
        #expect(viewModel.actionIssue != nil)
        #expect(viewModel.canControlPlayback)
    }

    @Test func locatingAFileThatIsNotMediaKeepsTheFailure() async throws {
        let recording = try await stored("Gone")
        try FileManager.default.removeItem(at: recording.media.url)
        viewModel.open(recordingID: recording.id)
        await viewModel.waitUntilSettled()
        let notMedia = environment.root.appending(path: "notes.mov")
        try Data("not a movie".utf8).write(to: notMedia)

        viewModel.finishLocating(.success(notMedia))
        await viewModel.waitUntilSettled()

        #expect(viewModel.actionIssue != nil)
        #expect(viewModel.playbackState == .failed(.mediaUnavailable(.missing)))
    }

    @Test func locatingTheFileRepointsTheSameEntryAndPlaysIt() async throws {
        let recording = try await stored("Gone")
        try FileManager.default.removeItem(at: recording.media.url)
        viewModel.open(recordingID: recording.id)
        await viewModel.waitUntilSettled()
        let located = try await environment.writePlayableMedia(hasVideo: true)

        viewModel.finishLocating(.success(located))
        await viewModel.waitUntilSettled()
        await viewModel.waitUntilSettled()

        #expect(viewModel.playbackState == .ready)
        #expect(viewModel.recording?.item.id == recording.id)
        let updated = try await repository.fetch(id: recording.id)
        #expect(updated?.media.url == located)
    }

    // MARK: - Switching and cleanup

    @Test func switchingReleasesThePreviousSessionAndClearsItsState() async throws {
        let first = try await opened("First")
        viewModel.togglePlayback()
        playback.emit(.timeChanged(30))
        let second = try await stored("Second")

        viewModel.open(recordingID: second.id)
        #expect(viewModel.recording == nil)
        #expect(viewModel.position == 0)
        #expect(viewModel.title.isEmpty)
        #expect(viewModel.openMedia == nil)
        #expect(playback.calls.last == .unload)
        await viewModel.waitUntilSettled()

        #expect(viewModel.recording?.item.id == second.id)
        #expect(viewModel.recording?.item.id != first.id)
        #expect(viewModel.playbackState == .ready)
        #expect(!viewModel.isPlaying)
    }

    @Test func aSlowLoadThatWasOvertakenDoesNotWin() async throws {
        let first = try await stored("First")
        let second = try await stored("Second")
        playback.holdsLoads = true

        viewModel.open(recordingID: first.id)
        await waitForHeldLoad()
        playback.holdsLoads = false
        viewModel.open(recordingID: second.id)
        await viewModel.waitUntilSettled()

        #expect(viewModel.recording?.item.id == second.id)
        #expect(viewModel.playbackState == .ready)
        #expect(playback.calls.filter { $0 == .load(first.media.url) }.count == 1)
        #expect(playback.calls.last(where: { if case .load = $0 { true } else { false } }) == .load(second.media.url))
    }

    @Test func closingTheWindowDuringALoadLeavesNothingBehind() async throws {
        let recording = try await stored()
        playback.holdsLoads = true
        viewModel.open(recordingID: recording.id)
        await waitForHeldLoad()

        viewModel.windowClosed()
        await Task.yield()

        #expect(viewModel.playbackState == .idle)
        #expect(viewModel.openMedia == nil)
        #expect(viewModel.recording == nil)
    }

    @Test func closingTheWindowStopsPlaybackAndReleasesEverything() async throws {
        _ = try await opened()
        viewModel.togglePlayback()

        viewModel.windowClosed()

        #expect(viewModel.playbackState == .idle)
        #expect(playback.calls.last == .unload)
        #expect(playback.onEvent == nil)
        #expect(viewModel.openMedia == nil)
        #expect(viewModel.recording == nil)
        #expect(viewModel.mediaInfo == nil)
        #expect(viewModel.position == 0)
    }

    @Test func closingCancelsASeekUnderway() async throws {
        _ = try await opened()
        playback.holdsSeeks = true
        viewModel.seek(to: 30)
        await waitForHeldSeek()

        viewModel.windowClosed()
        await Task.yield()

        #expect(viewModel.seekTask == nil)
        #expect(viewModel.pendingSeek == nil)
        #expect(viewModel.playbackState == .idle)
    }

    @Test func mediaAccessIsReleasedExactlyOnce() async throws {
        let closes = CloseCounter()
        let recording = try environment.makeRecording()
        let counting = CountingFileStore(base: environment.makeFileStore(), closes: closes)
        let service = environment.makeService(repository: repository, fileStore: counting)
        let model = ViewerViewModel(library: service, playback: playback)
        try await repository.insert(recording)

        model.open(recordingID: recording.id)
        await model.waitUntilSettled()
        #expect(await closes.value == 0)

        model.windowClosed()
        model.windowClosed()
        await Task.yield()

        #expect(await closes.value == 1)
    }
}
