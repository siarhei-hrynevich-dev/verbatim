import AppKit

/// AppKit integration that SwiftUI scenes do not provide: the Dock menu, recording indicators in the menu bar and
/// Dock, and confirmation before quitting during a recording.
///
/// It owns the Recorder view model, because the Dock menu and menu bar item act on the same recording as the
/// Recorder window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let recorderViewModel = RecorderViewModel(sources: .sample, scenario: .fromLaunchArguments())
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

    /// Quitting while recording asks first; Stop and Quit saves the recording before the app terminates.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let clock = recorderViewModel.activeClock else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Stop recording and quit?")
        let timer = RecordingClock.timerText(for: clock.elapsed(at: .now))
        let folder = recorderViewModel.sources.recordingsFolderPath
        alert.informativeText = String(
            localized: """
                The current recording (\(timer)) will be saved to \(folder) first. Transcription starts the next \
                time you open Verbatim.
                """
        )
        alert.addButton(withTitle: String(localized: "Stop and Quit"))
        let keepRecording = alert.addButton(withTitle: String(localized: "Keep Recording"))
        keepRecording.keyEquivalent = "\u{1b}"

        guard alert.runModal() == .alertFirstButtonReturn else {
            return .terminateCancel
        }
        recorderViewModel.stopRecording()
        return .terminateNow
    }
}
