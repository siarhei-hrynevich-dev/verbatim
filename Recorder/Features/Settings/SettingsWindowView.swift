import SwiftUI

/// The Settings window: General, AI Models, Storage and About tabs in the native settings toolbar. The window is
/// 620 pt wide and its height follows the selected tab.
struct SettingsWindowView: View {
    @Bindable var viewModel: SettingsViewModel
    /// Overrides the system accent color; `nil` follows the system.
    var accent: VerbatimAccent?
    var actions = SettingsWindowActions()

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                content(for: tab)
                    .frame(width: SettingsLayout.windowWidth)
                    .foregroundStyle(VerbatimColor.primaryText)
                    .verbatimAccent(accent)
                    .tabItem {
                        Label {
                            Text(tab.title)
                        } icon: {
                            tab.icon.image
                        }
                    }
                    .tag(tab)
            }
        }
        .focusEffectDisabled()
        .containerBackground(VerbatimColor.windowBackground, for: .window)
        .sheet(item: $viewModel.sheet) { sheet in
            sheetContent(for: sheet)
                .verbatimAccent(accent)
        }
        .task { await viewModel.runSimulation() }
        .verbatimAccent(accent)
    }

    @ViewBuilder
    private func content(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsView(viewModel: viewModel)
        case .models:
            ModelsSettingsView(viewModel: viewModel, showModelsInFinder: actions.showModelsInFinder)
        case .storage:
            StorageSettingsView(viewModel: viewModel, actions: actions)
        case .about:
            AboutSettingsView(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func sheetContent(for sheet: SettingsSheet) -> some View {
        switch sheet {
        case .removeModel(let modelID):
            if let model = viewModel.speechModel(withID: modelID) {
                RemoveModelSheet(
                    model: model,
                    cancel: viewModel.dismissSheet,
                    remove: { viewModel.confirmRemoval(of: modelID) }
                )
            }
        case .moveRecordings:
            MoveRecordingsSheet(
                destination: viewModel.data.proposedLocation,
                current: viewModel.location,
                recordingCount: viewModel.data.recordingCount,
                recordingsMegabytes: viewModel.data.recordingsMegabytes,
                cancel: viewModel.dismissSheet,
                keepRecordings: { viewModel.changeLocation(movingRecordings: false) },
                moveRecordings: { viewModel.changeLocation(movingRecordings: true) }
            )
        case .licenses:
            LicensesSheet(
                licenses: viewModel.data.licenses,
                openLicense: actions.openLicense,
                done: viewModel.dismissSheet
            )
        }
    }
}

/// Finder and Library integration that the Settings window hands to the app. None is implemented yet, so every
/// action defaults to doing nothing.
struct SettingsWindowActions {
    var showRecordingsInFinder: () -> Void = {}
    var showModelsInFinder: () -> Void = {}
    var reviewMissingRecordings: () -> Void = {}
    var openLicense: (ThirdPartyLicense) -> Void = { _ in }
}

extension SettingsTab {
    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .models: "AI Models"
        case .storage: "Storage"
        case .about: "About"
        }
    }

    var icon: VerbatimIcon {
        switch self {
        case .general: .gear
        case .models: .sparkles
        case .storage: .drive
        case .about: .info
        }
    }
}

#Preview("General") {
    SettingsWindowView(viewModel: SettingsViewModel(scenario: .general))
}

#Preview("AI Models · dark") {
    SettingsWindowView(viewModel: SettingsViewModel(scenario: .models))
        .preferredColorScheme(.dark)
}

#Preview("Storage · indigo") {
    SettingsWindowView(viewModel: SettingsViewModel(scenario: .storage), accent: .indigo)
}

#Preview("About") {
    SettingsWindowView(viewModel: SettingsViewModel(scenario: .about))
}
