import Foundation
import Testing

@testable import Recorder

@MainActor
struct SummarySettingsTests {
    let model = LanguageModelCatalog.curated[1]

    @Test func aModelUsesItsPresetUntilCustomized() {
        let preferences = SummaryPreferences(repository: InMemorySummarySettingsRepository())

        #expect(preferences.settings(for: model) == model.preset)
        #expect(!preferences.isCustomized(model))

        preferences.customize(model)
        #expect(preferences.isCustomized(model))
        #expect(preferences.settings(for: model) == model.preset)
    }

    @Test func editsAreKeptWithinRangeAndResetReturnsToThePreset() {
        let repository = InMemorySummarySettingsRepository()
        let preferences = SummaryPreferences(repository: repository)

        preferences.update(model) {
            $0.temperature = 0.9
            $0.topK = 500
        }

        #expect(preferences.settings(for: model).temperature == 0.9)
        #expect(preferences.settings(for: model).topK == SummarySettings.topKRange.upperBound)
        #expect(SummaryPreferences(repository: repository).settings(for: model).temperature == 0.9)

        preferences.resetToPreset(model)
        #expect(preferences.settings(for: model) == model.preset)
        #expect(repository.loadCustomSettings().isEmpty)
    }

    @Test func customSettingsBelongToTheirModel() {
        let preferences = SummaryPreferences(repository: InMemorySummarySettingsRepository())
        let other = LanguageModelCatalog.curated[0]

        preferences.update(model) { $0.batchTokens = 2_000 }

        #expect(preferences.settings(for: other) == other.preset)
    }

    @Test func theLanguageFollowsTheMacUntilChosenThenStays() {
        let repository = InMemorySummarySettingsRepository()

        let first = SummaryPreferences(repository: repository, preferredLanguages: ["de-DE"])
        #expect(first.language.code == "de")
        #expect(repository.loadLanguageCode() == nil)

        first.setLanguage(SummaryFixtures.russian)
        let relaunched = SummaryPreferences(repository: repository, preferredLanguages: ["de-DE"])
        #expect(relaunched.language == SummaryFixtures.russian)
    }

    @Test func aStoredLanguageNoLongerOfferedFallsBackToThePreferredOne() {
        let repository = InMemorySummarySettingsRepository()
        repository.saveLanguageCode("klingon")

        #expect(SummaryPreferences(repository: repository, preferredLanguages: ["fr"]).language.code == "fr")
    }

    @Test func userDefaultsKeepTheSelectionAndTheSettings() throws {
        let suite = "SummarySettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = UserDefaultsSummarySettingsRepository(defaults: defaults)
        var custom = model.preset
        custom.temperature = 0.55

        repository.saveSelectedModelID(model.id)
        repository.saveCustomSettings([model.id: custom])
        repository.saveLanguageCode("uk")
        #expect(repository.loadLanguageCode() == "uk")

        #expect(repository.loadSelectedModelID() == model.id)
        #expect(repository.loadCustomSettings() == [model.id: custom])

        defaults.set(Data("not json".utf8), forKey: "summaries.customSettings")
        #expect(repository.loadCustomSettings().isEmpty)
    }

    // MARK: - Settings window

    @Test func theSettingsFollowTheSelectedInstalledModel() async throws {
        let harness = LanguageModelHarness()
        let preferences = SummaryPreferences(repository: harness.settings)
        let viewModel = SummarySettingsViewModel(
            models: ModelSettingsViewModel(manager: harness.manager, systemActions: FakeSystemActions()),
            preferences: preferences
        )
        await harness.manager.reconcile()
        #expect(viewModel.model == nil)

        try await harness.install(model.id)

        #expect(viewModel.model == model)
        #expect(viewModel.settings == model.preset)
        #expect(!viewModel.isCustomized)
    }

    @Test func customizingResettingAndTurningItOff() async throws {
        let harness = LanguageModelHarness()
        let preferences = SummaryPreferences(repository: harness.settings)
        let viewModel = SummarySettingsViewModel(
            models: ModelSettingsViewModel(manager: harness.manager, systemActions: FakeSystemActions()),
            preferences: preferences
        )
        await harness.manager.reconcile()
        try await harness.install(model.id)

        viewModel.isCustomized = true
        viewModel.set(\.summaryTokens, to: 1_000)
        #expect(viewModel.settings?.summaryTokens == 1_000)
        #expect(viewModel.differsFromPreset)

        viewModel.resetToPreset()
        #expect(viewModel.isCustomized)
        #expect(!viewModel.differsFromPreset)

        viewModel.set(\.temperature, to: 1.0)
        viewModel.isCustomized = false
        #expect(viewModel.settings == model.preset)
    }
}
