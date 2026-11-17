import Foundation
import os

/// Stores the selected language model, the summary language and the summary settings customized per model. Settings are
/// JSON, so a value this version cannot read resets that model to its preset rather than failing.
struct UserDefaultsSummarySettingsRepository: SummarySettingsRepository {
    private enum Key {
        static let selectedModelID = "summaries.selectedModelID"
        static let customSettings = "summaries.customSettings"
        static let language = "summaries.language"
    }

    /// UserDefaults is documented as thread-safe, but is not marked Sendable.
    nonisolated(unsafe) let defaults: UserDefaults

    func loadSelectedModelID() -> String? {
        defaults.string(forKey: Key.selectedModelID)
    }

    func saveSelectedModelID(_ id: String?) {
        defaults.set(id, forKey: Key.selectedModelID)
    }

    func loadLanguageCode() -> String? {
        defaults.string(forKey: Key.language)
    }

    func saveLanguageCode(_ code: String) {
        defaults.set(code, forKey: Key.language)
    }

    func loadCustomSettings() -> [LanguageModel.ID: SummarySettings] {
        guard let data = defaults.data(forKey: Key.customSettings) else {
            return [:]
        }
        do {
            return try JSONDecoder().decode([LanguageModel.ID: SummarySettings].self, from: data)
        } catch {
            Self.logger.error("Stored summary settings are unreadable and reset: \(String(describing: error))")
            return [:]
        }
    }

    func saveCustomSettings(_ settings: [LanguageModel.ID: SummarySettings]) {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: Key.customSettings)
        } catch {
            Self.logger.error("Could not store summary settings: \(String(describing: error))")
        }
    }

    private static let logger = Logger(category: "Summaries")
}
