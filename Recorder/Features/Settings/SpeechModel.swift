import Foundation

/// A Whisper speech recognition model that can be installed on this Mac.
struct SpeechModel: Identifiable, Sendable {
    let id: String
    let name: String
    /// Download size in decimal megabytes.
    let sizeMegabytes: Int
    let summary: String
}

/// Installation state of a downloadable AI model.
enum ModelInstallState: Equatable, Sendable {
    case notInstalled
    /// `progress` is a fraction from 0 to 1.
    case downloading(progress: Double)
    /// Compiling for the Neural Engine after download. `progress` is a fraction from 0 to 1.
    case preparing(progress: Double)
    case installed

    var isInstalled: Bool {
        self == .installed
    }

    /// Downloading or preparing: the work can still be cancelled.
    var isBusy: Bool {
        switch self {
        case .downloading, .preparing: true
        case .notInstalled, .installed: false
        }
    }
}
