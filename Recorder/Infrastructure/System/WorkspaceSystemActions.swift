import AppKit

/// Opens System Settings and Finder.
struct WorkspaceSystemActions: SystemActions {
    func open(_ pane: SystemSettingsPane) async {
        guard let url = URL(string: Self.urlString(for: pane)) else {
            return
        }
        await MainActor.run {
            _ = NSWorkspace.shared.open(url)
        }
    }

    func openInFinder(_ url: URL) async {
        await MainActor.run {
            _ = NSWorkspace.shared.open(url)
        }
    }

    func revealInFinder(_ url: URL) async {
        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func openFile(_ url: URL) async -> Bool {
        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }

    private static func urlString(for pane: SystemSettingsPane) -> String {
        switch pane {
        case .screenRecording: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .microphone: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .storage: "x-apple.systempreferences:com.apple.settings.Storage"
        case .loginItems: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        }
    }
}
