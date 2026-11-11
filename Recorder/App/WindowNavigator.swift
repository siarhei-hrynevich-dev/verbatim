import AppKit
import SwiftUI

/// Opens the app's windows from AppKit integrations, such as the Dock menu and the menu bar item, which have no
/// SwiftUI environment. Window views install the environment's actions when they appear; the Recorder window opens
/// at launch, so they are available before any menu can be used.
@MainActor
final class WindowNavigator {
    static let recorderWindowID = "recorder"

    /// A window to show once the first window has appeared, for reviewing a design state passed at launch.
    enum LaunchRequest: Equatable {
        case library
        case viewer
        case settings
    }

    var launchRequests: [LaunchRequest] = []

    private var openWindow: OpenWindowAction?
    private var openSettingsAction: OpenSettingsAction?

    func install(openWindow: OpenWindowAction, openSettings: OpenSettingsAction) {
        self.openWindow = openWindow
        openSettingsAction = openSettings
        guard !launchRequests.isEmpty else {
            return
        }
        let requests = launchRequests
        launchRequests = []
        // Opening windows while the first one is still appearing is ignored, so wait for the next turn.
        Task { @MainActor in
            for request in requests {
                show(request)
            }
        }
    }

    func showRecorder() {
        show(windowID: Self.recorderWindowID)
    }

    func showLibrary() {
        show(windowID: LibraryWindowView.windowID)
    }

    /// Before the first window has appeared, as when a link launches the app, the Viewer opens once it has.
    func showViewer() {
        guard openWindow != nil else {
            if !launchRequests.contains(.viewer) {
                launchRequests.append(.viewer)
            }
            return
        }
        show(windowID: ViewerWindowView.windowID)
    }

    func showSettings() {
        NSApp.activate()
        openSettingsAction?()
    }

    private func show(_ request: LaunchRequest) {
        switch request {
        case .library: showLibrary()
        case .viewer: showViewer()
        case .settings: showSettings()
        }
    }

    private func show(windowID: String) {
        NSApp.activate()
        openWindow?(id: windowID)
    }
}

extension View {
    /// Hands this window's navigation actions to the navigator used by the Dock menu and menu bar item.
    func installsNavigation(into navigator: WindowNavigator) -> some View {
        modifier(NavigationInstaller(navigator: navigator))
    }
}

private struct NavigationInstaller: ViewModifier {
    let navigator: WindowNavigator

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.onAppear {
            navigator.install(openWindow: openWindow, openSettings: openSettings)
        }
    }
}
