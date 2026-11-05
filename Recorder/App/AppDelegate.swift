import AppKit
import SwiftUI

/// AppKit integration that SwiftUI scenes do not provide: the Dock menu, recording indicators in the menu bar and
/// Dock, and confirmation before quitting during a recording.
///
/// It holds the composition root's view models, because the Dock menu and menu bar item act on the same recording as
/// the Recorder window, and a finished recording must reach the Library with its window closed. The recording itself
/// lives in `RecordingCoordinator`, so it outlasts any window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModels = AppComposition.makeViewModels(
        recorderScenario: .fromLaunchArguments(),
        libraryScenario: .fromLaunchArguments(),
        viewerScenario: .fromLaunchArguments(),
        settingsScenario: .fromLaunchArguments()
    )
    let navigator = WindowNavigator()

    var recorderViewModel: RecorderViewModel {
        viewModels.recorder
    }

    var libraryViewModel: LibraryViewModel {
        viewModels.library
    }

    var viewerViewModel: ViewerViewModel {
        viewModels.viewer
    }

    var settingsViewModel: SettingsViewModel {
        viewModels.settings
    }

    var viewerVideoSurface: AnyView {
        viewModels.viewerVideoSurface
    }

    override init() {
        super.init()
        navigator.launchRequests = Self.launchRequests()
    }

    private var indicators: RecordingIndicators?
    /// The Recorder closed with Quit selected while capture was busy, so quitting waits until the file is saved.
    private var quitsWhenCaptureEnds = false

    /// Unit tests run inside this app. The queue opens the user's real library and can run jobs from it, so it stays
    /// shut; tests build their own coordinators on temporary folders.
    private static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

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
        let indicators = RecordingIndicators(
            recorder: recorderViewModel,
            navigator: navigator,
            preferences: viewModels.preferences
        )
        indicators.start()
        self.indicators = indicators
        viewModels.recordingPriority.start()
        // Reads metadata and file sizes only: no model is downloaded or loaded at launch. A job left unfinished by the
        // last run continues afterwards, and it is what loads a model, on demand.
        let modelManager = viewModels.modelManager
        let processing = viewModels.processing
        let resumesQueue = !Self.isHostingTests
        Task {
            await modelManager.reconcile()
            if resumesQueue {
                await processing.start()
            }
        }
    }

    // MARK: - Recorder window

    func recorderWindowDidOpen() {
        quitsWhenCaptureEnds = false
    }

    func recorderWindowDidClose() {
        guard viewModels.preferences.settings.closeBehavior == .quit else {
            return
        }
        quitsWhenCaptureEnds = true
        quitOnceCaptureEnds()
    }

    private func quitOnceCaptureEnds() {
        guard quitsWhenCaptureEnds else {
            return
        }
        let isCaptureBusy = withObservationTracking {
            recorderViewModel.isCaptureBusy
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.quitOnceCaptureEnds()
            }
        }
        if !isCaptureBusy {
            NSApp.terminate(nil)
        }
    }

    /// Closing the Recorder window must never end a recording.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// A Dock click without open windows brings back the Recorder, or the Library if the user prefers. An active
    /// recording always brings back the Recorder.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows else {
            return true
        }
        if viewModels.preferences.settings.opensRecorderOnDockClick || recorderViewModel.isCaptureBusy {
            navigator.showRecorder()
        } else {
            navigator.showLibrary()
        }
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
