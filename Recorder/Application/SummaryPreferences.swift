import Foundation
import Observation

/// The single owner of summary settings. Summaries are written in one language, whatever the transcript's, which
/// starts as the Mac's own when it is offered. Every model starts on its preset; the user may customize a copy, and
/// resetting forgets the copy, which returns the model to its preset, including any improvement a later version makes.
@MainActor
@Observable
final class SummaryPreferences {
    /// Only models the user customized have an entry.
    private(set) var customSettings: [LanguageModel.ID: SummarySettings]
    private(set) var language: SummaryLanguage

    @ObservationIgnored private let repository: any SummarySettingsRepository

    /// `preferredLanguages` decides the language until one is chosen; it is not stored until then, so a change of the
    /// Mac's language still applies.
    init(
        repository: any SummarySettingsRepository,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.repository = repository
        customSettings = repository.loadCustomSettings()
        language =
            repository.loadLanguageCode().flatMap(SummaryLanguage.init(code:))
            ?? .preferred(from: preferredLanguages)
    }

    func setLanguage(_ language: SummaryLanguage) {
        self.language = language
        repository.saveLanguageCode(language.code)
    }

    /// What summaries with this model use now, always within valid ranges.
    func settings(for model: LanguageModel) -> SummarySettings {
        (customSettings[model.id] ?? model.preset).clamped(toContext: model.contextTokens)
    }

    func isCustomized(_ model: LanguageModel) -> Bool {
        customSettings[model.id] != nil
    }

    /// Starts customizing from the preset, so nothing changes until a value is edited.
    func customize(_ model: LanguageModel) {
        guard !isCustomized(model) else {
            return
        }
        customSettings[model.id] = model.preset.clamped(toContext: model.contextTokens)
        save()
    }

    /// Edits the model's custom settings, starting them from the preset when there are none yet.
    func update(_ model: LanguageModel, _ change: (inout SummarySettings) -> Void) {
        var next = settings(for: model)
        change(&next)
        customSettings[model.id] = next.clamped(toContext: model.contextTokens)
        save()
    }

    func resetToPreset(_ model: LanguageModel) {
        guard customSettings.removeValue(forKey: model.id) != nil else {
            return
        }
        save()
    }

    private func save() {
        repository.saveCustomSettings(customSettings)
    }
}
