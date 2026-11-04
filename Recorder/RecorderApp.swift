import SwiftUI

@main
struct RecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var libraryViewModel = LibraryViewModel(
        scenario: LibraryPreviewScenario.fromLaunchArguments() ?? .list
    )
    @State private var viewerViewModel = ViewerViewModel(
        scenario: ViewerPreviewScenario.fromLaunchArguments() ?? .video
    )
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
                    libraryViewModel: libraryViewModel,
                    viewerViewModel: viewerViewModel,
                    settingsViewModel: settingsViewModel,
                    accent: $accent
                )
            #endif
        }

        Window("Recordings Library", id: LibraryWindowView.windowID) {
            // Finder actions, renaming and processing control are not connected yet.
            LibraryWindowView(
                viewModel: libraryViewModel,
                accent: accent,
                actions: LibraryWindowActions(
                    openRecording: openInViewer,
                    openTranscript: { openInViewer($0, at: nil) },
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
            // Finder actions, export and processing control are not connected yet.
            ViewerWindowView(
                viewModel: viewerViewModel,
                accent: accent,
                actions: ViewerWindowActions(backToLibrary: navigator.showLibrary)
            )
            .installsNavigation(into: navigator)
        }
        .defaultSize(width: ViewerLayout.windowWidth, height: ViewerLayout.windowHeight)
        .windowToolbarStyle(.unified(showsTitle: false))
        .restorationBehavior(.disabled)

        // Opened from the Recorder gear, the Library sidebar, the Dock menu or ⌘,.
        Settings {
            SettingsWindowView(viewModel: settingsViewModel, accent: accent)
        }
    }

    /// Shows a Library recording in the Viewer, at a transcript position when one is given.
    private func openInViewer(_ id: LibraryItem.ID, at timestamp: TimeInterval?) {
        guard let item = libraryViewModel.items.first(where: { $0.id == id }) else {
            return
        }
        viewerViewModel.open(item, at: timestamp)
        navigator.showViewer()
    }

    private var navigator: WindowNavigator {
        appDelegate.navigator
    }
}
