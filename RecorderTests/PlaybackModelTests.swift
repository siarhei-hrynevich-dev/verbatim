import Foundation
import Testing

@testable import Recorder

struct PlaybackModelTests {
    @Test(arguments: [
        (PlaybackState.idle, PlaybackState.loading),
        (.loading, .ready),
        (.loading, .failed(.corruptedMedia)),
        (.ready, .playing),
        (.ready, .paused),
        (.playing, .paused),
        (.playing, .ended),
        (.paused, .playing),
        (.paused, .ended),
        (.ended, .playing),
        (.ended, .paused),
        (.playing, .failed(.seekFailed)),
        (.failed(.corruptedMedia), .loading),
        (.playing, .loading),
        (.playing, .idle)
    ])
    func allowsTheLifecycle(from: PlaybackState, to next: PlaybackState) {
        #expect(from.allowsTransition(to: next))
    }

    @Test(arguments: [
        (PlaybackState.idle, PlaybackState.playing),
        (.idle, .ready),
        (.idle, .failed(.corruptedMedia)),
        (.loading, .playing),
        (.loading, .ended),
        (.failed(.corruptedMedia), .playing),
        (.ended, .ready),
        (.playing, .ready)
    ])
    func refusesTransitionsThatSkipLoading(from: PlaybackState, to next: PlaybackState) {
        #expect(!from.allowsTransition(to: next))
    }

    @Test(arguments: [
        (PlaybackState.ready, true),
        (.playing, true),
        (.paused, true),
        (.ended, true),
        (.idle, false),
        (.loading, false),
        (.failed(.seekFailed), false)
    ])
    func onlyLoadedStatesAcceptControls(state: PlaybackState, isLoaded: Bool) {
        #expect(state.isLoaded == isLoaded)
    }

    @Test(arguments: [
        (30.0, 30.0),
        (-5.0, 0.0),
        (500.0, 120.0),
        (120.0, 120.0)
    ])
    func seekPositionsStayWithinTheRecording(requested: TimeInterval, expected: TimeInterval) {
        #expect(PlaybackTimeline.validatedPosition(requested, duration: 120) == expected)
    }

    @Test(arguments: [TimeInterval.nan, .infinity, -.infinity])
    func seekPositionsMustBeNumbers(requested: TimeInterval) {
        #expect(PlaybackTimeline.validatedPosition(requested, duration: 120) == nil)
    }

    @Test func aPositionNearTheLastFrameCountsAsTheEnd() {
        #expect(PlaybackTimeline.isAtEnd(120, duration: 120))
        #expect(PlaybackTimeline.isAtEnd(119.99, duration: 120))
        #expect(!PlaybackTimeline.isAtEnd(119, duration: 120))
        #expect(!PlaybackTimeline.isAtEnd(0, duration: 0))
    }

    @Test func theMediaDurationWinsOverTheStoredOne() {
        #expect(PlaybackTimeline.effectiveDuration(media: 95, stored: 100) == 95)
        #expect(PlaybackTimeline.effectiveDuration(media: nil, stored: 100) == 100)
        #expect(PlaybackTimeline.effectiveDuration(media: 0, stored: 100) == 100)
        #expect(PlaybackTimeline.effectiveDuration(media: .nan, stored: 100) == 100)
    }

    @Test func onlySizableDurationDifferencesCountAsDisagreement() {
        #expect(PlaybackTimeline.durationsDisagree(media: 90, stored: 100))
        #expect(!PlaybackTimeline.durationsDisagree(media: 99.5, stored: 100))
    }

    @Test(arguments: [
        (0.0, "00:00:00", "0:00"),
        (59.9, "00:00:59", "0:59"),
        (61.0, "00:01:01", "1:01"),
        (4_360.0, "01:12:40", "1:12:40"),
        (-3.0, "00:00:00", "0:00")
    ])
    func durationsFormat(seconds: TimeInterval, timer: String, library: String) {
        #expect(RecordingClock.timerText(for: seconds) == timer)
        #expect(LibraryFormat.duration(seconds) == library)
    }

    @Test func libraryErrorsTranslateToPlaybackFailures() {
        #expect(PlaybackFailure(LibraryError.recordingNotFound) == .recordingNotFound)
        #expect(PlaybackFailure(LibraryError.mediaUnavailable(.missing)) == .mediaUnavailable(.missing))
        #expect(PlaybackFailure(LibraryError.corruptedMedia) == .corruptedMedia)
        #expect(PlaybackFailure(PlaybackFailure.unsupportedFormat) == .unsupportedFormat)
        guard case .loadFailed = PlaybackFailure(LibraryError.persistenceFailed(detail: "disk full")) else {
            Issue.record("Other Library failures should read as a failed load")
            return
        }
    }

    @Test(arguments: [
        (PlaybackFailure.mediaUnavailable(.missing), ViewerIssue.Recovery.locateFile),
        (.mediaUnavailable(.accessDenied), .locateFile),
        (.mediaUnavailable(.volumeUnavailable), .retry),
        (.corruptedMedia, .showInFinder),
        (.unsupportedFormat, .showInFinder),
        (.loadFailed(detail: "x"), .retry),
        (.playbackFailed(detail: "x"), .retry)
    ])
    func everyFailureLeadsWithAFix(failure: PlaybackFailure, firstRecovery: ViewerIssue.Recovery) {
        #expect(ViewerIssue(failure).recoveries.first == firstRecovery)
    }

    @Test func aRecordingThatLeftTheLibraryHasNothingToRecover() {
        #expect(ViewerIssue(.recordingNotFound).recoveries.isEmpty)
    }

    @Test func transcriptFilesAreFoundAmongARecordingsFiles() {
        #expect(RecordingFileLayout.transcriptFileName(in: ["recording.mov", "recording.json"]) == nil)
        #expect(
            RecordingFileLayout.transcriptFileName(in: ["recording.mov", "transcript.json", "transcript.txt"])
                == "transcript.txt"
        )
    }
}
