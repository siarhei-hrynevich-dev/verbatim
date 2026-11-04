import Foundation
import Testing

@testable import Recorder

/// Design-review scenarios, which show states without touching capture.
@MainActor
struct RecorderViewModelTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func startsReadyWithLastUsedDefaults() {
        let viewModel = RecorderViewModel()

        #expect(viewModel.phase == .ready)
        #expect(viewModel.status == .ready)
        #expect(viewModel.captureMode == .screen)
        #expect(viewModel.selectedDisplay?.name == "Built-in Display")
        #expect(viewModel.canStartRecording)
    }

    @Test func screenPermissionBlocksVideoUntilAudioOnlyIsChosen() {
        let viewModel = RecorderViewModel(scenario: .permission)
        #expect(viewModel.status == .needsAttention)
        #expect(!viewModel.canStartRecording)

        viewModel.performIssueSecondaryAction()

        #expect(viewModel.captureMode == .audioOnly)
        #expect(viewModel.issue == .screenRecordingPermission)
        #expect(viewModel.canStartRecording)
    }

    @Test func blockedStartDoesNotBeginRecording() {
        let viewModel = RecorderViewModel(scenario: .permission)

        viewModel.startRecording(at: start)

        #expect(viewModel.phase == .ready)
    }

    @Test(arguments: [
        (RecorderPreviewScenario.microphone, CaptureMode.screen),
        (.source, .screen),
        (.folder, .screen),
        (.disk, .screen)
    ])
    func fallbackActionsResolveNonBlockingIssues(scenario: RecorderPreviewScenario, expectedMode: CaptureMode) {
        let viewModel = RecorderViewModel(scenario: scenario)

        viewModel.performIssueSecondaryAction()

        #expect(viewModel.issue == nil)
        #expect(viewModel.captureMode == expectedMode)
    }

    @Test func fallbackActionsApplyTheirSettings() {
        let microphone = RecorderViewModel(scenario: .microphone)
        microphone.performIssueSecondaryAction()
        #expect(!microphone.isMicrophoneEnabled)

        let disk = RecorderViewModel(scenario: .disk)
        disk.performIssueSecondaryAction()
        #expect(disk.quality == .hd720)
    }

    @Test func recordingPausesResumesAndStopsWithSavedNotice() {
        let viewModel = RecorderViewModel()

        viewModel.startRecording(at: start)
        #expect(viewModel.status == .recording)

        viewModel.togglePause(at: start.addingTimeInterval(10))
        #expect(viewModel.status == .paused)

        viewModel.togglePause(at: start.addingTimeInterval(15))
        guard case .recording(let clock) = viewModel.phase else {
            Issue.record("Expected an active recording")
            return
        }
        #expect(clock.elapsed(at: start.addingTimeInterval(20)) == 15)

        viewModel.stopRecording()
        #expect(viewModel.phase == .ready)
        #expect(viewModel.savedRecordingTitle != nil)
    }

    @Test func recordingScenarioShowsTheDesignElapsedTime() {
        let now = Date()
        let viewModel = RecorderViewModel(scenario: .picker)

        viewModel.apply(.recording, at: now)

        guard case .recording(let clock) = viewModel.phase else {
            Issue.record("Expected an active recording")
            return
        }
        #expect(RecordingClock.timerText(for: clock.elapsed(at: now)) == "00:12:34")
    }

    @Test func pickerScenarioSelectsWindowSource() {
        #expect(RecorderViewModel(scenario: .picker).captureMode == .window)
    }
}

struct RecordingClockTests {
    @Test func excludesPausedTime() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var clock = RecordingClock(startedAt: start)

        clock.pause(at: start.addingTimeInterval(30))
        #expect(clock.elapsed(at: start.addingTimeInterval(90)) == 30)

        clock.resume(at: start.addingTimeInterval(90))
        #expect(clock.elapsed(at: start.addingTimeInterval(100)) == 40)
    }

    @Test(arguments: [(0.0, "00:00:00"), (754.9, "00:12:34"), (3_725.0, "01:02:05")])
    func formatsTimer(seconds: Double, expected: String) {
        #expect(RecordingClock.timerText(for: seconds) == expected)
    }
}

struct RecorderPreviewScenarioTests {
    @Test func readsScenarioFromDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "RecorderPreviewScenarioTests"))
        defer { defaults.removePersistentDomain(forName: "RecorderPreviewScenarioTests") }

        defaults.set("recording", forKey: RecorderPreviewScenario.launchArgumentKey)
        #expect(RecorderPreviewScenario.fromLaunchArguments(defaults) == .recording)

        defaults.set("unknown", forKey: RecorderPreviewScenario.launchArgumentKey)
        #expect(RecorderPreviewScenario.fromLaunchArguments(defaults) == .idle)

        defaults.removeObject(forKey: RecorderPreviewScenario.launchArgumentKey)
        #expect(RecorderPreviewScenario.fromLaunchArguments(defaults) == nil)
    }
}
