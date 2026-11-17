import Foundation

/// Stores Settings choices as individual defaults, so a value that is no longer valid only resets itself. Which models
/// are installed is deliberately not here: that comes from the disk.
struct UserDefaultsSettingsRepository: SettingsRepository {
    private enum Key {
        static let showsMenuBarIcon = "settings.showsMenuBarIcon"
        static let opensRecorderOnDockClick = "settings.opensRecorderOnDockClick"
        static let closeBehavior = "settings.closeBehavior"
        static let selectedModelID = "settings.selectedModelID"
        static let transcriptionLanguage = "settings.transcriptionLanguage"
    }

    /// UserDefaults is documented as thread-safe, but is not marked Sendable.
    nonisolated(unsafe) let defaults: UserDefaults

    func loadSettings() -> AppSettings {
        var settings = AppSettings()
        if let shows = defaults.object(forKey: Key.showsMenuBarIcon) as? Bool {
            settings.showsMenuBarIcon = shows
        }
        if let opens = defaults.object(forKey: Key.opensRecorderOnDockClick) as? Bool {
            settings.opensRecorderOnDockClick = opens
        }
        if let behavior = defaults.string(forKey: Key.closeBehavior).flatMap(CloseBehavior.init) {
            settings.closeBehavior = behavior
        }
        settings.transcriptionLanguage = TranscriptionLanguage(
            storedCode: defaults.string(forKey: Key.transcriptionLanguage)
        )
        return settings
    }

    func saveSettings(_ settings: AppSettings) {
        defaults.set(settings.showsMenuBarIcon, forKey: Key.showsMenuBarIcon)
        defaults.set(settings.opensRecorderOnDockClick, forKey: Key.opensRecorderOnDockClick)
        defaults.set(settings.closeBehavior.rawValue, forKey: Key.closeBehavior)
        defaults.set(settings.transcriptionLanguage.code, forKey: Key.transcriptionLanguage)
    }

    func loadSelectedModelID() -> SpeechModel.ID? {
        defaults.string(forKey: Key.selectedModelID)
    }

    func saveSelectedModelID(_ id: SpeechModel.ID?) {
        defaults.set(id, forKey: Key.selectedModelID)
    }
}
