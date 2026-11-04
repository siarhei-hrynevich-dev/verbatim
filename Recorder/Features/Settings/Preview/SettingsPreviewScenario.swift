import Foundation

/// Settings states that can be shown without real models, storage or updates, matching section “05 Settings” of
/// the design.
///
/// Select one at launch with `-SettingsPreviewScenario <rawValue>`, which also opens the Settings window, from the
/// Debug menu in Debug builds, or in SwiftUI previews.
enum SettingsPreviewScenario: String, CaseIterable, Identifiable, Sendable {
    case general
    case models
    case removeModel
    case storage
    case moveRecordings
    case about
    case licenses

    static let launchArgumentKey = "SettingsPreviewScenario"

    /// The design confirms removing Base.
    static let sampleRemovedModelID: SpeechModel.ID = "base"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general: "General"
        case .models: "AI Models"
        case .removeModel: "Remove Model"
        case .storage: "Storage"
        case .moveRecordings: "Change Location"
        case .about: "About"
        case .licenses: "Licenses"
        }
    }

    var tab: SettingsTab {
        switch self {
        case .general: .general
        case .models, .removeModel: .models
        case .storage, .moveRecordings: .storage
        case .about, .licenses: .about
        }
    }

    var sheet: SettingsSheet? {
        switch self {
        case .removeModel: .removeModel(Self.sampleRemovedModelID)
        case .moveRecordings: .moveRecordings
        case .licenses: .licenses
        case .general, .models, .storage, .about: nil
        }
    }

    /// Reads the scenario from launch arguments; `nil` when none, or an unknown one, is given.
    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> SettingsPreviewScenario? {
        defaults.string(forKey: launchArgumentKey).flatMap(SettingsPreviewScenario.init(rawValue:))
    }
}
