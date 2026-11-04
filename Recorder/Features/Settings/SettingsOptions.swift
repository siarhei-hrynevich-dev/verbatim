import Foundation

/// The Settings window's tabs, in toolbar order.
enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case models
    case storage
    case about

    var id: String {
        rawValue
    }
}

/// A sheet shown over the Settings window.
enum SettingsSheet: Identifiable, Equatable, Sendable {
    case removeModel(SpeechModel.ID)
    case moveRecordings
    case licenses

    var id: String {
        switch self {
        case .removeModel(let modelID): "remove-\(modelID)"
        case .moveRecordings: "move"
        case .licenses: "licenses"
        }
    }
}

/// What happens to the app when the Recorder window closes.
enum CloseBehavior: CaseIterable, Sendable {
    case keepRunning
    case quit
}

/// Progress of the manual update check.
enum UpdateCheckStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate
}

/// A transcription language choice; `nil` code means automatic detection.
struct TranscriptionLanguage: Identifiable, Hashable, Sendable {
    let code: String?
    let name: String

    var id: String {
        code ?? "auto"
    }
}

/// A recordings folder and the volume that holds it.
struct StorageLocation: Equatable, Sendable {
    /// The folder as shown to the user, such as `~/Movies/Verbatim`.
    let path: String
    let volumeName: String
    let freeBytes: Int64

    var folderName: String {
        (path as NSString).lastPathComponent
    }
}

/// A third-party component and its license.
struct ThirdPartyLicense: Identifiable, Sendable {
    let name: String
    let license: String

    var id: String {
        name
    }
}
