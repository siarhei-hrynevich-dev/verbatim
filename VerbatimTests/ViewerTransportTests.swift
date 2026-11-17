import Foundation
import Testing

@testable import Verbatim

/// The transport controls and timeline, on a real Library in a temporary folder with the player replaced.
@MainActor
struct ViewerTransportTests: ViewerPlaybackTesting {
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

    // MARK: - Transport

    @Test func playAndPauseMoveThroughTheStates() async throws {
        _ = try await opened()

        viewModel.togglePlayback()
        #expect(viewModel.playbackState == .playing)
        #expect(playback.calls.last == .play)

        viewModel.togglePlayback()
        #expect(viewModel.playbackState == .paused)
        #expect(playback.calls.last == .pause)
    }

    @Test func controlsDoNothingWithoutLoadedMedia() async {
        viewModel.togglePlayback()
        viewModel.seek(to: 10)
        viewModel.beginScrubbing()
        viewModel.scrub(to: 10)
        await viewModel.waitUntilSettled()

        #expect(viewModel.playbackState == .idle)
        #expect(viewModel.position == 0)
        #expect(playback.calls.isEmpty)
    }

    @Test func thePlayerStoppingOnItsOwnIsReflected() async throws {
        _ = try await opened()
        viewModel.togglePlayback()

        playback.emit(.paused)

        #expect(viewModel.playbackState == .paused)
    }

    @Test func timeUpdatesMoveThePlayhead() async throws {
        _ = try await opened()
        viewModel.togglePlayback()

        playback.emit(.timeChanged(7.5))
        #expect(viewModel.position == 7.5)

        playback.emit(.timeChanged(.nan))
        #expect(viewModel.position == 7.5)
    }

    @Test func seeksStayInRangeAndIgnoreNonNumbers() async throws {
        _ = try await opened()

        viewModel.seek(to: -10)
        #expect(viewModel.position == 0)
        viewModel.seek(to: .nan)
        #expect(viewModel.position == 0)
        viewModel.skip(by: 15)
        #expect(viewModel.position == 15)
        await viewModel.waitUntilSettled()

        #expect(playback.currentTime == 15)
    }

    @Test func speedVolumeAndMuteReachThePlayer() async throws {
        _ = try await opened()

        viewModel.cycleSpeed()
        #expect(playback.calls.last == .rate(1.5))

        viewModel.setVolume(0.25)
        #expect(viewModel.volume == 0.25)
        #expect(playback.calls.last == .volume(0.25))

        viewModel.setVolume(4)
        #expect(viewModel.volume == 1)

        viewModel.toggleMute()
        #expect(viewModel.isMuted)
        #expect(playback.calls.last == .muted(true))

        viewModel.setVolume(0.5)
        #expect(!viewModel.isMuted)
        #expect(playback.calls.last == .muted(false))
    }

    @Test func volumeAndMuteCarryOverToTheNextRecordingButSpeedDoesNot() async throws {
        _ = try await opened("First")
        viewModel.setVolume(0.3)
        viewModel.toggleMute()
        viewModel.cycleSpeed()

        _ = try await opened("Second")

        #expect(viewModel.speed == .normal)
        #expect(viewModel.volume == 0.3)
        #expect(playback.calls.suffix(3) == [.rate(1), .volume(0.3), .muted(true)])
    }

    // MARK: - Scrubbing

    @Test func aDragHoldsPlaybackAndTheThumbThenResumes() async throws {
        _ = try await opened()
        viewModel.togglePlayback()
        playback.holdsSeeks = true

        viewModel.beginScrubbing()
        #expect(viewModel.playbackState == .paused)

        viewModel.scrub(to: 30)
        await waitForHeldSeek()
        playback.emit(.timeChanged(3))
        #expect(viewModel.position == 30)

        playback.holdsSeeks = false
        viewModel.endScrubbing(at: 40)
        #expect(viewModel.position == 40)
        playback.emit(.timeChanged(3))
        #expect(viewModel.position == 40)

        playback.releaseSeeks()
        await viewModel.waitUntilSettled()
        #expect(viewModel.playbackState == .playing)
        #expect(playback.calls.last == .play)
        #expect(playback.seeks.last == .seek(40, .exact))
    }

    @Test func aClickOnTheTimelineWithoutMovementSeeksThere() async throws {
        try await opened()

        viewModel.beginScrubbing()
        viewModel.endScrubbing(at: 25)
        await viewModel.waitUntilSettled()

        #expect(viewModel.position == 25)
        #expect(playback.seeks == [.seek(25, .exact)])
    }

    @Test func aDragEndedWithTheCurrentPositionFreesTheTimeline() async throws {
        try await opened()
        viewModel.togglePlayback()
        viewModel.beginScrubbing()
        viewModel.scrub(to: 25)

        viewModel.endScrubbing(at: viewModel.position)
        await viewModel.waitUntilSettled()
        playback.emit(.timeChanged(26))

        #expect(viewModel.position == 26)
        #expect(viewModel.isPlaying)
    }

    @Test func aDragOverAPausedRecordingStaysPaused() async throws {
        _ = try await opened()

        viewModel.beginScrubbing()
        viewModel.scrub(to: 30)
        viewModel.endScrubbing(at: 30)
        await viewModel.waitUntilSettled()

        #expect(viewModel.playbackState == .paused)
        #expect(!playback.calls.contains(.play))
    }

    @Test func fastDragsSkipPositionsThePlayerHasNoTimeFor() async throws {
        _ = try await opened()
        playback.holdsSeeks = true

        viewModel.beginScrubbing()
        viewModel.scrub(to: 10)
        await waitForHeldSeek()
        for target in stride(from: 11.0, through: 20, by: 1) {
            viewModel.scrub(to: target)
        }
        playback.holdsSeeks = false
        viewModel.endScrubbing(at: 21)
        playback.releaseSeeks()
        await viewModel.waitUntilSettled()

        #expect(playback.seeks == [.seek(10, .approximate), .seek(21, .exact)])
    }

    @Test func aNewSeekDuringAnOldOnesReportDoesNotJump() async throws {
        _ = try await opened()
        playback.holdsSeeks = true

        viewModel.seek(to: 20)
        await waitForHeldSeek()
        playback.emit(.timeChanged(1))

        #expect(viewModel.position == 20)
        playback.holdsSeeks = false
        playback.releaseSeeks()
        await viewModel.waitUntilSettled()
    }

    // MARK: - Completion

    @Test func reachingTheEndEndsPlaybackAtTheDuration() async throws {
        _ = try await opened()
        viewModel.togglePlayback()

        playback.emit(.paused)
        playback.emit(.playedToEnd)

        #expect(viewModel.playbackState == .ended)
        #expect(viewModel.position == viewModel.duration)
    }

    @Test func playingAgainFromTheEndRestartsFromTheBeginning() async throws {
        _ = try await opened()
        viewModel.togglePlayback()
        playback.emit(.playedToEnd)

        viewModel.togglePlayback()
        await viewModel.waitUntilSettled()

        #expect(viewModel.playbackState == .playing)
        #expect(viewModel.position == 0)
        #expect(playback.seeks.last == .seek(0, .exact))
        #expect(playback.calls.last == .play)
    }

    @Test func seekingBackFromTheEndPausesThereAndResumes() async throws {
        _ = try await opened()
        viewModel.togglePlayback()
        playback.emit(.playedToEnd)

        viewModel.seek(to: 10)
        await viewModel.waitUntilSettled()
        #expect(viewModel.playbackState == .paused)
        #expect(viewModel.position == 10)

        viewModel.togglePlayback()
        #expect(viewModel.playbackState == .playing)
    }

    @Test func seekingToTheEndWhilePausedEnds() async throws {
        _ = try await opened()

        viewModel.seek(to: 60)
        await viewModel.waitUntilSettled()

        #expect(viewModel.playbackState == .ended)
    }

    @Test func aTimeReportAfterTheEndDoesNotMoveThePlayhead() async throws {
        _ = try await opened()
        viewModel.togglePlayback()
        playback.emit(.playedToEnd)

        playback.emit(.timeChanged(3))

        #expect(viewModel.position == viewModel.duration)
    }
}
