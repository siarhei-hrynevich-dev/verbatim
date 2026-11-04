import SwiftUI

/// App lifecycle settings. The close-behavior note changes with the menu bar setting.
struct GeneralSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection {
                SettingsToggleRow(
                    title: "Launch at Login",
                    detail: String(localized: "Starts in the background, ready from the menu bar or Dock."),
                    isOn: $viewModel.launchesAtLogin
                )
                GroupedDivider(leadingInset: 12)
                SettingsToggleRow(
                    title: "Show Menu Bar Icon",
                    detail: String(
                        localized: "Start and stop recordings and see elapsed time without opening a window."
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

            SettingsSection {
                SettingsToggleRow(
                    title: "Notify When Processing Finishes",
                    detail: String(
                        localized: "A notification when a recording’s transcript and search index are ready."
                    ),
                    isOn: $viewModel.notifiesWhenProcessingFinishes
                )
            }
        }
        .padding(SettingsLayout.contentPadding)
        .fixedSize(horizontal: false, vertical: true)
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
