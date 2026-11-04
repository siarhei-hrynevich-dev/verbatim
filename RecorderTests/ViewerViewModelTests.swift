import Foundation
import Testing

@testable import Recorder

@MainActor
struct ViewerViewModelTests {
    private let data = ViewerPreviewData.sample()

    @Test(arguments: [
        (ViewerPreviewScenario.video, "Architecture Review"),
        (.audio, "1:1 with Maya"),
        (.processing, "Weekly Team Sync"),
        (.failed, "Design Critique"),
        (.unprocessed, "Onboarding Walkthrough")
    ])
    func scenariosShowTheDesignRecording(scenario: ViewerPreviewScenario, title: String) {
        let viewModel = ViewerViewModel(previewData: data, scenario: scenario)

        #expect(viewModel.recording.item.title == title)
        #expect(viewModel.title == title)
    }

    @Test func scenariosMapTranscriptStates() {
        #expect(ViewerViewModel(previewData: data, scenario: .video).recording.transcriptState == .ready)
        #expect(
            ViewerViewModel(previewData: data, scenario: .processing).recording.transcriptState
                == .processing(progress: 0.64)
        )
        #expect(
            ViewerViewModel(previewData: data, scenario: .failed).recording.transcriptState == .failed(stoppedAt: 1_900)
        )
        #expect(ViewerViewModel(previewData: data, scenario: .unprocessed).recording.transcriptState == .notProcessed)
        #expect(ViewerViewModel(previewData: data, scenario: .processing).lines.isEmpty)
    }

    @Test func videoScenarioPlaysOnTheEngineLine() {
        let viewModel = ViewerViewModel(previewData: data, scenario: .video)

        #expect(viewModel.isPlaying)
        #expect(viewModel.activeLineIndex == 16)
        #expect(viewModel.lines[16].text == "I think we should start with the recording engine.")
    }

    @Test func playbackAdvancesWithSpeedAndStopsAtTheEnd() {
        let viewModel = ViewerViewModel(previewData: data, scenario: .audio)
        viewModel.togglePlayback()

        viewModel.cycleSpeed()
        viewModel.advance(by: 2)
        #expect(viewModel.position == 83)

        viewModel.seek(to: viewModel.duration - 1)
        viewModel.advance(by: 5)
        #expect(viewModel.position == viewModel.duration)
        #expect(!viewModel.isPlaying)
    }

    @Test func pausedPlaybackDoesNotAdvance() {
        let viewModel = ViewerViewModel(previewData: data, scenario: .audio)

        viewModel.advance(by: 10)

        #expect(viewModel.position == 80)
    }

    @Test func skippingAndSeekingStayWithinTheRecording() {
        let viewModel = ViewerViewModel(previewData: data, scenario: .audio)

        viewModel.skip(by: -100)
        #expect(viewModel.position == 0)

        viewModel.seekToLine(at: 7)
        #expect(viewModel.position == 75)
        #expect(viewModel.activeLineIndex == 7)
    }

    @Test func speedCyclesThroughTheDesignSteps() {
        let viewModel = ViewerViewModel(previewData: data, scenario: .video)

        viewModel.cycleSpeed()
        #expect(viewModel.speed == .fast)
        viewModel.cycleSpeed()
        #expect(viewModel.speed == .double)
        viewModel.cycleSpeed()
        #expect(viewModel.speed == .normal)
    }

    @Test func matchStepsWrapAndMoveThePlayhead() {
        let viewModel = ViewerViewModel(previewData: data, scenario: .search)
        #expect(viewModel.matchingLineIndices == [12, 16, 20, 21, 23])
        // The design's search state highlights the second match, the line at the playhead.
        #expect(viewModel.currentMatchLineIndex == 16)
        #expect(viewModel.activeLineIndex == 16)

        viewModel.pauseFollowingPlayback()
        viewModel.showNextMatch()
        #expect(viewModel.currentMatchLineIndex == 20)
        #expect(viewModel.position == 318)
        #expect(viewModel.isFollowingPlayback)

        viewModel.showPreviousMatch()
        viewModel.showPreviousMatch()
        #expect(viewModel.currentMatchLineIndex == 12)

        viewModel.showPreviousMatch()
        #expect(viewModel.currentMatchLineIndex == 23)
    }

    @Test func newQueryRestartsAtTheFirstMatch() {
        let viewModel = ViewerViewModel(previewData: data, scenario: .search)

        viewModel.updateSearchText("CAPTURE")

        #expect(viewModel.matchingLineIndices == [4, 17, 22])
        #expect(viewModel.currentMatchLineIndex == 4)
    }

    @Test func followingPlaybackPausesAndResumes() {
        let viewModel = ViewerViewModel(previewData: data, scenario: .video)

        viewModel.pauseFollowingPlayback()
        #expect(!viewModel.isFollowingPlayback)

        viewModel.resumeFollowingPlayback()
        #expect(viewModel.isFollowingPlayback)
    }

    @Test(arguments: [ViewerPreviewScenario.failed, .unprocessed])
    func processingStartsFromFailedOrUnprocessed(scenario: ViewerPreviewScenario) {
        let viewModel = ViewerViewModel(previewData: data, scenario: scenario)

        viewModel.startProcessing()

        #expect(viewModel.recording.transcriptState == .processing(progress: 0.01))
    }

    @Test func openingFromTheLibraryShowsTheTimestamp() throws {
        let viewModel = ViewerViewModel(previewData: data, scenario: .audio)
        let planning = try #require(data.item(titled: "Q4 Planning"))

        viewModel.open(planning, at: 3_090)

        #expect(viewModel.recording.item.id == planning.id)
        #expect(viewModel.position == 3_090)
        #expect(!viewModel.isPlaying)
        #expect(viewModel.searchText.isEmpty)
    }

    @Test func readsScenarioFromDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "ViewerPreviewScenarioTests"))
        defer { defaults.removePersistentDomain(forName: "ViewerPreviewScenarioTests") }

        #expect(ViewerPreviewScenario.fromLaunchArguments(defaults) == nil)
        defaults.set("failed", forKey: ViewerPreviewScenario.launchArgumentKey)
        #expect(ViewerPreviewScenario.fromLaunchArguments(defaults) == .failed)
    }
}
