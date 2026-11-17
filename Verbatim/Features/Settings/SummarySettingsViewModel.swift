import Foundation
import Observation

/// The summary models and the settings of the selected one. Settings follow the model's preset until the user turns
/// on customizing; turning it off, or Reset, returns to the preset. Values belong to `SummaryPreferences`.
@MainActor
@Observable
final class SummarySettingsViewModel {
    let models: ModelSettingsViewModel<LanguageModel>
    private let preferences: SummaryPreferences

    init(models: ModelSettingsViewModel<LanguageModel>, preferences: SummaryPreferences) {
        self.models = models
        self.preferences = preferences
    }

    /// What summaries are written in, for every model and whatever the transcript's language.
    var language: SummaryLanguage {
        get { preferences.language }
        set { preferences.setLanguage(newValue) }
    }

    /// The model the settings apply to: the selected one, once it is installed.
    var model: LanguageModel? {
        if case .ready(let model) = models.manager.selectionStatus {
            return model
        }
        return nil
    }

    var isCustomized: Bool {
        get { model.map(preferences.isCustomized) ?? false }
        set {
            guard let model else {
                return
            }
            if newValue {
                preferences.customize(model)
            } else {
                preferences.resetToPreset(model)
            }
        }
    }

    /// What summaries use now.
    var settings: SummarySettings? {
        model.map(preferences.settings(for:))
    }

    /// Whether anything differs from the preset, which is when Reset has something to do.
    var differsFromPreset: Bool {
        guard let model, let settings else {
            return false
        }
        return settings != model.preset.clamped(toContext: model.contextTokens)
    }

    /// The largest batch the model's context allows with the current note length.
    var batchTokenLimit: Int {
        guard let model, let settings else {
            return SummarySettings.batchTokenRange.upperBound
        }
        let limit = model.contextTokens - settings.batchNoteTokens - SummarySettings.promptOverheadTokens
        return max(SummarySettings.batchTokenRange.lowerBound, min(SummarySettings.batchTokenRange.upperBound, limit))
    }

    func set<Value>(_ keyPath: WritableKeyPath<SummarySettings, Value>, to value: Value) {
        guard let model else {
            return
        }
        preferences.update(model) { $0[keyPath: keyPath] = value }
    }

    /// Back to the preset values, staying in customizing so they can be edited again.
    func resetToPreset() {
        guard let model else {
            return
        }
        preferences.resetToPreset(model)
        preferences.customize(model)
    }
}
