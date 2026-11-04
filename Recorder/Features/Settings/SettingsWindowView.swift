import SwiftUI

/// The Settings window: General, AI Models, Storage and About tabs in the native settings toolbar. The window is
/// 620 pt wide and its height follows the selected tab.
struct SettingsWindowView: View {
    @Bindable var viewModel: SettingsViewModel
    /// Overrides the system accent color; `nil` follows the system.
    var accent: VerbatimAccent?

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
        .sheet(isPresented: $viewModel.isShowingLicenses) {
            LicensesSheet(licenses: ThirdPartyLicense.shipped, done: viewModel.dismissLicenses)
                .verbatimAccent(accent)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { viewModel.issue != nil }, set: { _ in viewModel.dismissIssue() }),
            presenting: viewModel.issue
        ) { _ in
            Button("OK", action: viewModel.dismissIssue)
        } message: { issue in
            Text(issue)
        }
        .verbatimAccent(accent)
    }

    @ViewBuilder
    private func content(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsView(viewModel: viewModel)
        case .models:
            ModelSettingsView(viewModel: viewModel.models)
        case .storage:
            StorageSettingsView(viewModel: viewModel)
        case .about:
            AboutSettingsView(viewModel: viewModel)
        }
    }
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
    SettingsWindowView(viewModel: .preview(.general))
}

#Preview("AI Models · dark") {
    SettingsWindowView(viewModel: .preview(.models))
        .preferredColorScheme(.dark)
}

#Preview("Storage · indigo") {
    SettingsWindowView(viewModel: .preview(.storage), accent: .indigo)
}

#Preview("About") {
    SettingsWindowView(viewModel: .preview(.about))
}
