import SwiftUI

/// Version, update check, and project links.
struct AboutSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 22) {
            header
            VStack(spacing: 6) {
                GroupedSection {
                    sourceCodeRow
                    GroupedDivider(leadingInset: 37)
                    Button(action: viewModel.showLicenses) {
                        linkRow(icon: .file, title: "Open-Source Licenses") {
                            IconView(.chevronRight, size: 12)
                                .foregroundStyle(VerbatimColor.secondaryText)
                        }
                    }
                    .buttonStyle(AboutRowButtonStyle())
                    GroupedDivider(leadingInset: 37)
                    linkRow(icon: .retry, title: "Check for Updates Automatically") {
                        Toggle("Check for updates automatically", isOn: $viewModel.checksForUpdatesAutomatically)
                            .toggleStyle(.verbatimSwitch)
                    }
                }
                Text("© 2026 Verbatim contributors. Released under the MIT License.")
                    .font(.system(size: 11))
                    .foregroundStyle(VerbatimColor.secondaryText)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.top, 28)
        .padding(.horizontal, SettingsLayout.contentPadding)
        .padding(.bottom, SettingsLayout.contentPadding)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        VStack(spacing: 6) {
            VerbatimAppIcon(size: 88)
                .padding(.bottom, 6)
            Text("Verbatim")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.22)
                .accessibilityAddTraits(.isHeader)
            Text("Version \(viewModel.data.version) (\(viewModel.data.build))")
                .font(.system(size: 12))
                .foregroundStyle(VerbatimColor.secondaryText)
                .textSelection(.enabled)
            VStack(spacing: 8) {
                Button("Check for Updates…", action: viewModel.checkForUpdates)
                    .buttonStyle(.verbatim(.secondary, size: .dialog))
                    .disabled(viewModel.updateStatus == .checking)
                updateStatusLine
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
    }

    private var updateStatusLine: some View {
        HStack(spacing: 5) {
            switch viewModel.updateStatus {
            case .idle:
                Text("Last checked today at \(viewModel.data.lastUpdateCheck)")
            case .checking:
                IconView(.loader, size: 12)
                Text("Checking for updates…")
            case .upToDate:
                IconView(.check, size: 12)
                    .foregroundStyle(VerbatimColor.green)
                Text("Verbatim \(viewModel.data.version) is the latest version.")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(VerbatimColor.secondaryText)
        .frame(minHeight: 14)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var sourceCodeRow: some View {
        let row = linkRow(icon: .code, title: "Source Code on GitHub") {
            Text(verbatim: "github.com/verbatim-app/verbatim")
                .font(.system(size: 12))
                .foregroundStyle(VerbatimColor.secondaryText)
            IconView(.externalLink, size: 11)
                .foregroundStyle(VerbatimColor.secondaryText)
        }
        if let url = viewModel.data.sourceCodeURL {
            Link(destination: url) { row }
                .buttonStyle(AboutRowButtonStyle())
        } else {
            row
        }
    }

    private func linkRow(
        icon: VerbatimIcon,
        title: LocalizedStringKey,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 10) {
            IconView(icon, size: 15)
                .foregroundStyle(VerbatimColor.secondaryText)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(VerbatimColor.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .contentShape(Rectangle())
    }
}

/// A full-width row inside a grouped section that acts as a button or link.
private struct AboutRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .focusRing(cornerRadius: 6)
    }
}

/// The app icon drawn from shapes: a screen around a record dot on a light squircle.
struct VerbatimAppIcon: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(LinearGradient(colors: [.white, Self.squircleBottom], startPoint: .top, endPoint: .bottom))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
            }
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: size * 0.06)
                        .fill(Self.screen)
                        .frame(width: size * 0.66, height: size * 0.46)
                        .offset(x: size * 0.17, y: size * 0.22)
                    RoundedRectangle(cornerRadius: size * 0.02)
                        .fill(Self.stand)
                        .frame(width: size * 0.2, height: size * 0.05)
                        .offset(x: size * 0.4, y: size * 0.72)
                    Circle()
                        .fill(Self.record)
                        .frame(width: size * 0.23, height: size * 0.23)
                        .offset(x: size * 0.385, y: size * 0.335)
                }
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.22), radius: size * 0.04, y: size * 0.03)
            .accessibilityLabel("Verbatim app icon")
    }

    private static let squircleBottom = Color(red: 230 / 255, green: 230 / 255, blue: 235 / 255)
    private static let screen = Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255)
    private static let stand = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    private static let record = Color(red: 1, green: 59 / 255, blue: 48 / 255)
}
