import Foundation

/// What happens to the app when the Recorder window closes.
enum CloseBehavior: String, CaseIterable, Sendable {
    case keepRunning
    case quit
}

/// App behavior the user can change in Settings. Each value has a real effect today; nothing is stored for features
/// that do not exist yet.
struct AppSettings: Equatable, Sendable {
    var showsMenuBarIcon = true
    var opensRecorderOnDockClick = true
    var closeBehavior = CloseBehavior.keepRunning
}

/// Whether the app opens at login. The system owns this, so it is read back rather than stored.
enum LoginItemStatus: Equatable, Sendable {
    case enabled
    case disabled
    /// Registered, but the user has to allow it in System Settings.
    case requiresApproval
}
