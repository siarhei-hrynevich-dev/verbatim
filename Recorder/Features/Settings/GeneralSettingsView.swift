import SwiftUI

/// App lifecycle settings. The close-behavior note changes with the menu bar setting.
struct GeneralSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection {
                SettingsRow(title: "Launch at Login", detail: viewModel.loginItemNote) {
                    if viewModel.loginItemStatus == .requiresApproval {
                        Button("Open System Settings", action: viewModel.openLoginItemSettings)
                            .buttonStyle(.verbatim(.secondary, size: .inline))
                    }
                    Toggle("Launch at Login", isOn: $viewModel.launchesAtLogin)
                        .toggleStyle(.verbatimSwitch)
                }
                GroupedDivider(leadingInset: 12)
                SettingsToggleRow(
                    title: "Show Menu Bar Icon",
                    detail: String(
                        localized: "See elapsed time and stop or pause without opening a window, while recording."
                    ),
                    isOn: $viewModel.showsMenuBarIcon
                )
                GroupedDivider(leadingInset: 12)
                SettingsToggleRow(
                    title: "Open Recorder When Dock Icon Is Clicked",
                    detail: viewModel.dockClickNote,
                    isOn: $viewModel.opensRecorderOnDockClick
                )
            }

            SettingsSection(footnote: viewModel.closeBehaviorNote) {
                SettingsRow(title: "When the Recorder Window Closes", isCompact: true) {
                    SettingsPopUpMenu(
                        accessibilityLabel: "When the Recorder Window Closes",
                        selectionTitle: viewModel.closeBehavior.title,
                        selection: $viewModel.closeBehavior
                    ) {
                        ForEach(CloseBehavior.allCases, id: \.self) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                }
            }
        }
        .padding(SettingsLayout.contentPadding)
        .fixedSize(horizontal: false, vertical: true)
        // The system owns this, and the user can change it in System Settings at any time.
        .onAppear(perform: viewModel.refreshLoginItemStatus)
    }
}

extension CloseBehavior {
    var title: String {
        switch self {
        case .keepRunning: String(localized: "Keep Verbatim Running")
        case .quit: String(localized: "Quit Verbatim")
        }
    }
}
