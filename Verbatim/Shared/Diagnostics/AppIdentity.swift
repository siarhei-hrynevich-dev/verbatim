import Foundation
import os

/// The app's identity at run time. The bundle identifier is defined once, in the Xcode build settings, and read from
/// the bundle here so that logs and queue labels follow it.
enum AppIdentity {
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "Verbatim"
}

extension Logger {
    /// A logger in the app's subsystem, which is its bundle identifier.
    init(category: String) {
        self.init(subsystem: AppIdentity.bundleIdentifier, category: category)
    }
}
