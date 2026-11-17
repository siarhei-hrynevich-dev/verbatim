import Foundation
import Observation

/// The single owner of app behavior preferences. Settings edits them; the menu bar item and the app delegate act on
/// them. Every change is saved at once.
@MainActor
@Observable
final class AppPreferences {
    private(set) var settings: AppSettings

    @ObservationIgnored private let repository: any SettingsRepository

    init(repository: any SettingsRepository) {
        self.repository = repository
        settings = repository.loadSettings()
    }

    func update(_ change: (inout AppSettings) -> Void) {
        change(&settings)
        repository.saveSettings(settings)
    }
}
