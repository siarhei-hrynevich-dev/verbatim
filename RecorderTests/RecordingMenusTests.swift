import AppKit
import Testing

@testable import Recorder

@MainActor
struct RecordingMenusTests {
    private let navigator = WindowNavigator()

    @Test func idleDockMenuOffersNewRecordingFirst() {
        let recorder = RecorderViewModel(scenario: .idle)

        let menu = RecordingMenus.dockMenu(recorder: recorder, navigator: navigator)

        #expect(
            menu.items.map(\.title) == ["New Recording", "Open Recorder", "Recordings Library", "", "Settings…"]
        )
    }

    @Test func recordingDockMenuStartsWithTheTimer() {
        let recorder = RecorderViewModel(scenario: .recording)

        let menu = RecordingMenus.dockMenu(recorder: recorder, navigator: navigator)

        #expect(menu.items.first?.title.hasPrefix("● Recording — 00:12:3") == true)
        #expect(menu.items.first?.isEnabled == false)
        #expect(menu.items.dropFirst(2).map(\.title) == ["Open Recorder", "Stop Recording", "Recordings Library"])
    }

    @Test func stopFromTheDockMenuEndsTheRecording() throws {
        let recorder = RecorderViewModel(scenario: .recording)
        let menu = RecordingMenus.dockMenu(recorder: recorder, navigator: navigator)
        let stop = try #require(menu.items.first { $0.title == "Stop Recording" })

        _ = stop.target?.perform(stop.action, with: stop)

        #expect(recorder.phase == .ready)
        #expect(recorder.hasSavedRecording)
    }

    @Test func statusMenuDescribesSourceAndAudio() {
        let recorder = RecorderViewModel(scenario: .recording)

        let menu = RecordingMenus.statusMenu(recorder: recorder, navigator: navigator)

        #expect(recorder.menuTitle == "Recording · Built-in Display")
        #expect(recorder.menuDetail == "Microphone on · System audio on")
        #expect(menu.items.map(\.title).contains("Pause Recording"))

        recorder.togglePause()
        #expect(recorder.menuTitle == "Paused · Built-in Display")
        let pausedMenu = RecordingMenus.statusMenu(recorder: recorder, navigator: navigator)
        #expect(pausedMenu.items.map(\.title).contains("Resume Recording"))
    }
}
