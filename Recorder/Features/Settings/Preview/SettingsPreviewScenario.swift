import Foundation

/// Settings states that can be shown with sample data and simulated downloads, matching section “05 Settings” of the
/// design as far as the app implements it.
///
/// Select one at launch with `-SettingsPreviewScenario <rawValue>`, which also opens the Settings window, from the
/// Debug menu in Debug builds, or in SwiftUI previews.
enum SettingsPreviewScenario: String, CaseIterable, Identifiable, Sendable {
    case general
    case models
    case removeModel
    case noModels
    case agents
    case storage
    case about
    case licenses

    static let launchArgumentKey = "SettingsPreviewScenario"

    /// The design confirms removing Base.
    static let sampleRemovedModelID: SpeechModel.ID = "openai_whisper-base"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general: "General"
        case .models: "AI Models"
        case .removeModel: "Remove Model"
        case .noModels: "No Models Installed"
        case .agents: "Agents"
        case .storage: "Storage"
        case .about: "About"
        case .licenses: "Licenses"
        }
    }

    var tab: SettingsTab {
        switch self {
        case .general: .general
        case .models, .removeModel, .noModels: .models
        case .agents: .agents
        case .storage: .storage
        case .about, .licenses: .about
        }
    }

    /// Reads the scenario from launch arguments; `nil` when none, or an unknown one, is given.
    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> SettingsPreviewScenario? {
        defaults.string(forKey: launchArgumentKey).flatMap(SettingsPreviewScenario.init(rawValue:))
    }
}
