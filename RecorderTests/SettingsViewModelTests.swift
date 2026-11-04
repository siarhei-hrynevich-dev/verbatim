import Foundation
import Testing

@testable import Recorder

@MainActor
struct SettingsViewModelTests {
    private func advance(_ viewModel: SettingsViewModel, until condition: () -> Bool) {
        for _ in 0..<1_000 where !condition() {
            viewModel.advanceSimulation()
        }
    }

    @Test(arguments: [
        (SettingsPreviewScenario.general, SettingsTab.general, nil),
        (.models, .models, nil),
        (.removeModel, .models, SettingsSheet.removeModel("base")),
        (.storage, .storage, nil),
        (.moveRecordings, .storage, .moveRecordings),
        (.about, .about, nil),
        (.licenses, .about, .licenses)
    ])
    func scenariosSelectTabAndSheet(scenario: SettingsPreviewScenario, tab: SettingsTab, sheet: SettingsSheet?) {
        let viewModel = SettingsViewModel(scenario: scenario)

        #expect(viewModel.selectedTab == tab)
        #expect(viewModel.sheet == sheet)
    }

    @Test func closeNoteFollowsTheMenuBarSetting() {
        let viewModel = SettingsViewModel()
        #expect(viewModel.closeBehaviorNote.hasPrefix("Verbatim stays in the menu bar and Dock."))

        viewModel.showsMenuBarIcon = false
        #expect(viewModel.closeBehaviorNote.hasPrefix("Verbatim stays in the Dock."))

        viewModel.closeBehavior = .quit
        #expect(viewModel.closeBehaviorNote.hasPrefix("Verbatim quits when the window closes."))
    }

    @Test func downloadProgressesThroughPreparingToInstalled() {
        let viewModel = SettingsViewModel(scenario: .models)

        viewModel.download("tiny")
        #expect(viewModel.state(of: "tiny") == .downloading(progress: 0))

        viewModel.advanceSimulation()
        guard case .downloading(let progress) = viewModel.state(of: "tiny") else {
            Issue.record("Expected a download in progress")
            return
        }
        #expect(progress > 0)

        advance(viewModel) { viewModel.state(of: "tiny") == .installed }
        #expect(viewModel.state(of: "tiny") == .installed)
    }

    @Test func cancellingStopsDownloadingAndPreparing() {
        let viewModel = SettingsViewModel(scenario: .models)

        viewModel.cancelDownload("medium")
        viewModel.cancelDownload("small")
        viewModel.advanceSimulation()

        #expect(viewModel.state(of: "medium") == .notInstalled)
        #expect(viewModel.state(of: "small") == .notInstalled)
    }

    @Test func defaultModelCannotBeRemovedUntilAnotherIsDefault() {
        let viewModel = SettingsViewModel(scenario: .models)
        #expect(!viewModel.canRemove("turbo"))

        viewModel.requestRemoval(of: "turbo")
        #expect(viewModel.sheet == nil)

        viewModel.makeDefault("base")
        #expect(viewModel.isDefault("base"))
        #expect(viewModel.canRemove("turbo"))
    }

    @Test func confirmingRemovalUninstallsTheModel() {
        let viewModel = SettingsViewModel(scenario: .removeModel)

        viewModel.confirmRemoval(of: "base")

        #expect(viewModel.state(of: "base") == .notInstalled)
        #expect(viewModel.sheet == nil)
        #expect(viewModel.unusedSpeechModel == nil)
    }

    @Test func searchIndexFinishesAndRebuilds() {
        let viewModel = SettingsViewModel(scenario: .models)
        #expect(viewModel.indexStatus == .indexing(indexed: 46, total: 48))

        advance(viewModel) { viewModel.indexStatus == .upToDate }
        #expect(viewModel.indexStatus == .upToDate)

        viewModel.rebuildSearchIndex()
        #expect(viewModel.indexStatus == .indexing(indexed: 0, total: 48))

        viewModel.isSemanticSearchEnabled = false
        #expect(viewModel.indexStatus == .off)
        #expect(!viewModel.isSearchIndexAvailable)
    }

    @Test func removingTheEmbeddingModelWaitsForIt() {
        let viewModel = SettingsViewModel(scenario: .models)

        viewModel.removeEmbeddingModel()
        #expect(viewModel.indexStatus == .waitingForModel)

        viewModel.downloadEmbeddingModel()
        advance(viewModel) { viewModel.embeddingState == .installed }
        #expect(viewModel.embeddingState == .installed)
    }

    @Test func storageTotalsMatchTheDesign() {
        let viewModel = SettingsViewModel(scenario: .storage)

        #expect(SettingsFormat.size(megabytes: viewModel.modelsMegabytes) == SettingsFormat.size(megabytes: 1_860))
        #expect(viewModel.cacheMegabytes == 410)
        #expect(viewModel.totalMegabytes == 40_470)

        viewModel.clearPreviewCache()
        #expect(viewModel.cacheMegabytes == 186)
    }

    @Test func changingLocationUsesTheChosenFolder() {
        let viewModel = SettingsViewModel(scenario: .moveRecordings)

        viewModel.changeLocation(movingRecordings: false)

        #expect(viewModel.location.volumeName == "Archive")
        #expect(viewModel.sheet == nil)
    }

    @Test func updateCheckFinishesAfterASimulatedDelay() {
        let viewModel = SettingsViewModel(scenario: .about)

        viewModel.checkForUpdates()
        #expect(viewModel.updateStatus == .checking)

        advance(viewModel) { viewModel.updateStatus == .upToDate }
        #expect(viewModel.updateStatus == .upToDate)
    }
}

struct SettingsFormatTests {
    @Test(arguments: [(75.0, "75 MB"), (570.0, "570 MB")])
    func formatsMegabytes(megabytes: Double, expected: String) {
        #expect(SettingsFormat.size(megabytes: megabytes) == expected)
    }

    @Test func downloadCaptionSaysWhenLessThanAMinuteIsLeft() {
        let caption = SettingsFormat.downloadCaption(progress: 0.38, sizeMegabytes: 1_500, secondsLeft: 31)

        #expect(caption.hasPrefix("570 MB of "))
        #expect(caption.hasSuffix("less than a minute left"))
    }

    @Test func downloadCaptionRoundsMinutes() {
        let caption = SettingsFormat.downloadCaption(progress: 0, sizeMegabytes: 3_100, secondsLeft: 103)

        #expect(caption.hasSuffix("about 2 min left"))
    }
}

struct SettingsPreviewScenarioTests {
    @Test func readsScenarioFromDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "SettingsPreviewScenarioTests"))
        defer { defaults.removePersistentDomain(forName: "SettingsPreviewScenarioTests") }

        #expect(SettingsPreviewScenario.fromLaunchArguments(defaults) == nil)

        defaults.set("licenses", forKey: SettingsPreviewScenario.launchArgumentKey)
        #expect(SettingsPreviewScenario.fromLaunchArguments(defaults) == .licenses)
    }
}
