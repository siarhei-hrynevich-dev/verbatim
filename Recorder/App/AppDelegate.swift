import AppKit

/// AppKit integration that SwiftUI scenes do not provide: the Dock menu, recording indicators in the menu bar and
/// Dock, and confirmation before quitting during a recording.
///
/// It holds the composition root's Recorder view model, because the Dock menu and menu bar item act on the same
/// recording as the Recorder window. The recording itself lives in `RecordingCoordinator`, so it outlasts any window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let recorderViewModel = AppComposition.makeRecorderViewModel(scenario: .fromLaunchArguments())
    let navigator = WindowNavigator()

    override init() {
        super.init()
        navigator.launchRequests = Self.launchRequests()
    }

    private var indicators: RecordingIndicators?

    /// Design states passed at launch open their windows, so each state can be reviewed directly.
    private static func launchRequests() -> [WindowNavigator.LaunchRequest] {
        var requests: [WindowNavigator.LaunchRequest] = []
        if LibraryPreviewScenario.fromLaunchArguments() != nil {
            requests.append(.library)
        }
        if ViewerPreviewScenario.fromLaunchArguments() != nil {
            requests.append(.viewer)
        }
        if SettingsPreviewScenario.fromLaunchArguments() != nil {
            requests.append(.settings)
        }
        return requests
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let indicators = RecordingIndicators(recorder: recorderViewModel, navigator: navigator)
        indicators.start()
        self.indicators = indicators
    }

    /// Closing the Recorder window must never end a recording.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// A Dock click without open windows brings back the Recorder (with an active recording, if any), never the
    /// Library.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows else {
            return true
        }
        navigator.showRecorder()
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        RecordingMenus.dockMenu(recorder: recorderViewModel, navigator: navigator)
    }

    /// Quitting while recording asks first. Stop and Quit waits until the media is finalized, and quits even if that
    /// fails, because whatever was captured stays on disk.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let clock = recorderViewModel.activeClock, !confirmStopAndQuit(clock: clock) {
            return .terminateCancel
        }
        guard recorderViewModel.isCaptureBusy else {
            recorderViewModel.stopRecording()
            return .terminateNow
        }
        Task {
            await recorderViewModel.stopAndWait()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func confirmStopAndQuit(clock: RecordingClock) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Stop recording and quit?")
        let timer = RecordingClock.timerText(for: clock.elapsed(at: .now))
        let folder = recorderViewModel.recordingsFolderPath
        alert.informativeText = String(
            localized: "The current recording (\(timer)) will be saved to \(folder) first."
        )
        alert.addButton(withTitle: String(localized: "Stop and Quit"))
        let keepRecording = alert.addButton(withTitle: String(localized: "Keep Recording"))
        keepRecording.keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }
}
