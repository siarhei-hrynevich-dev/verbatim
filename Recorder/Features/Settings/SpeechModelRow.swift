import SwiftUI

/// One Whisper model: name, size, status chip and description, download progress while installing, and its
/// actions. The default model keeps a faint accent tint, and its Remove button is disabled.
struct SpeechModelRow: View {
    let model: SpeechModel
    let viewModel: SettingsViewModel

    var body: some View {
        let state = viewModel.state(of: model.id)
        let isDefault = viewModel.isDefault(model.id)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(SettingsFormat.size(megabytes: model.sizeMegabytes))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(VerbatimColor.secondaryText)
                    chip(for: state, isDefault: isDefault)
                }
                Text(model.summary)
                    .font(.system(size: 12))
                    .lineSpacing(1.5)
                    .foregroundStyle(VerbatimColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                progress(for: state)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions(for: state, isDefault: isDefault)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(isDefault ? VerbatimColor.accent.opacity(0.06) : .clear)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func chip(for state: ModelInstallState, isDefault: Bool) -> some View {
        switch state {
        case .installed where isDefault:
            ModelStatusChip(title: String(localized: "Default"), icon: .check, iconColor: .white, style: .prominent)
        case .installed:
            ModelStatusChip(title: String(localized: "Installed"), icon: .check, iconColor: VerbatimColor.green)
        case .downloading(let progress):
            ModelStatusChip(
                title: String(localized: "Downloading \(Int((progress * 100).rounded()))%"),
                icon: .download,
                iconColor: VerbatimColor.accent
            )
        case .preparing:
            ModelStatusChip(title: String(localized: "Preparing"), icon: .loader, iconColor: VerbatimColor.orange)
        case .notInstalled:
            ModelStatusChip(
                title: String(localized: "Not Installed"),
                icon: .circle,
                iconColor: VerbatimColor.tertiaryText,
                style: .outlined
            )
        }
    }

    @ViewBuilder
    private func progress(for state: ModelInstallState) -> some View {
        switch state {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 4) {
                SettingsProgressBar(fraction: progress)
                caption(
                    SettingsFormat.downloadCaption(
                        progress: progress,
                        sizeMegabytes: model.sizeMegabytes,
                        secondsLeft: viewModel.secondsLeft(downloading: model, progress: progress)
                    )
                )
                .monospacedDigit()
            }
            .padding(.top, 5)
        case .preparing:
            VStack(alignment: .leading, spacing: 4) {
                IndeterminateProgressBar()
                caption(String(localized: "Optimizing for this Mac’s Neural Engine. This happens once per model."))
            }
            .padding(.top, 5)
        case .notInstalled, .installed:
            EmptyView()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(VerbatimColor.secondaryText)
    }

    @ViewBuilder
    private func actions(for state: ModelInstallState, isDefault: Bool) -> some View {
        HStack(spacing: 6) {
            switch state {
            case .notInstalled:
                DownloadButton { viewModel.download(model.id) }
            case .downloading, .preparing:
                Button {
                    viewModel.cancelDownload(model.id)
                } label: {
                    IconView(.xCircle, size: 16)
                }
                .buttonStyle(SettingsIconButtonStyle())
                .help("Cancel")
                .accessibilityLabel("Cancel \(model.name) download")
            case .installed:
                if !isDefault {
                    Button("Make Default") { viewModel.makeDefault(model.id) }
                        .buttonStyle(.verbatim(.secondary, size: .inline))
                }
                Button {
                    viewModel.requestRemoval(of: model.id)
                } label: {
                    IconView(.trash, size: 14)
                }
                .buttonStyle(SettingsIconButtonStyle())
                .disabled(isDefault)
                .help(isDefault ? "Choose another default model before removing this one" : "Remove model")
                .accessibilityLabel("Remove \(model.name)")
            }
        }
        .fixedSize()
    }
}

/// The 22 pt Download button with an accent download icon.
struct DownloadButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                IconView(.download, size: 12)
                    .foregroundStyle(VerbatimColor.accent)
                Text("Download")
            }
        }
        .buttonStyle(.verbatim(.secondary, size: .inline))
    }
}
