import SwiftUI

@main
struct RecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settingsViewModel = SettingsViewModel(
        scenario: SettingsPreviewScenario.fromLaunchArguments() ?? .general
    )
    @State private var accent = VerbatimAccent.fromLaunchArguments()

    var body: some Scene {
        // One Recorder window: the Dock icon, Dock menu and menu bar item bring back this window, including during
        // an active recording.
        Window("Verbatim", id: WindowNavigator.recorderWindowID) {
            RecorderWindowView(
                viewModel: appDelegate.recorderViewModel,
                openLibrary: navigator.showLibrary,
                openSettings: navigator.showSettings
            )
            .verbatimAccent(accent)
            .installsNavigation(into: navigator)
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        // The Recorder is the default screen on launch, even when other windows are restored.
        .defaultLaunchBehavior(.presented)
        .commands {
            #if DEBUG
                DebugCommands(
                    recorderViewModel: appDelegate.recorderViewModel,
                    libraryViewModel: appDelegate.libraryViewModel,
                    viewerViewModel: appDelegate.viewerViewModel,
                    settingsViewModel: settingsViewModel,
                    accent: $accent
                )
            #endif
        }

        Window("Recordings Library", id: LibraryWindowView.windowID) {
            LibraryWindowView(
                viewModel: appDelegate.libraryViewModel,
                accent: accent,
                actions: LibraryWindowActions(
                    openRecording: { openRecording($0, at: $1) },
                    openTranscript: { openRecording($0, at: nil) },
                    newRecording: navigator.showRecorder,
                    openSettings: navigator.showSettings
                )
            )
            .installsNavigation(into: navigator)
        }
        .defaultSize(width: LibraryLayout.windowWidth, height: LibraryLayout.windowHeight)
        .windowToolbarStyle(.unified(showsTitle: false))
        // The Recorder is the screen on launch; other windows are not restored from the previous session.
        .restorationBehavior(.disabled)

        Window("Viewer", id: ViewerWindowView.windowID) {
            // Export and processing control are not connected yet.
            ViewerWindowView(
                viewModel: appDelegate.viewerViewModel,
                accent: accent,
                actions: ViewerWindowActions(backToLibrary: navigator.showLibrary),
                videoSurface: appDelegate.viewerVideoSurface
            )
            .installsNavigation(into: navigator)
        }
        .defaultSize(width: ViewerLayout.windowWidth, height: ViewerLayout.windowHeight)
        .windowToolbarStyle(.unified(showsTitle: false))
        .restorationBehavior(.disabled)
        // Windows other than the app's first scene are auxiliary by default, and those cannot enter full screen.
        .windowManagerRole(.principal)

        // Opened from the Recorder gear, the Library sidebar, the Dock menu or ⌘,.
        Settings {
            SettingsWindowView(viewModel: settingsViewModel, accent: accent)
        }
    }

    /// Shows a recording in the Viewer, at a transcript position when one is given. The Library's sample recordings
    /// have no entry to look up, so its design scenarios hand over the sample itself.
    private func openRecording(_ id: LibraryItem.ID, at timestamp: TimeInterval?) {
        let library = appDelegate.libraryViewModel
        if !library.isPreviewing {
            appDelegate.viewerViewModel.open(recordingID: id, at: timestamp)
        } else if let sample = library.items.first(where: { $0.id == id }) {
            appDelegate.viewerViewModel.open(sample, at: timestamp)
        } else {
            return
        }
        navigator.showViewer()
    }

    private var navigator: WindowNavigator {
        appDelegate.navigator
    }
}
