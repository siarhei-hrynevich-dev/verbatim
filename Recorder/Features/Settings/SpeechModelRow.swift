import SwiftUI

/// One Whisper model: name, size, status chip and description, progress or failure while installing, and its actions.
/// The selected model keeps a faint accent tint.
struct SpeechModelRow: View {
    let row: ModelSettingsViewModel.Row
    let viewModel: ModelSettingsViewModel

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(row.model.name)
                        .font(.system(size: 13, weight: .semibold))
                    if let sizeBytes = row.sizeBytes {
                        Text(SettingsFormat.size(bytes: sizeBytes))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(VerbatimColor.secondaryText)
                    }
                    chip
                }
                Text(row.model.summary)
                    .font(.system(size: 12))
                    .lineSpacing(1.5)
                    .foregroundStyle(VerbatimColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                caption(row.model.languageSupport)
                progress
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(row.isSelected ? VerbatimColor.accent.opacity(0.06) : .clear)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var chip: some View {
        switch row.state {
        case .installed where row.isSelected:
            ModelStatusChip(title: String(localized: "Selected"), icon: .check, iconColor: .white, style: .prominent)
        case .installed:
            ModelStatusChip(title: String(localized: "Installed"), icon: .check, iconColor: VerbatimColor.green)
        case .downloading(let progress):
            ModelStatusChip(
                title: String(localized: "Downloading \(Int(((progress?.fraction ?? 0) * 100).rounded()))%"),
                icon: .download,
                iconColor: VerbatimColor.accent
            )
        case .waitingForRecording:
            ModelStatusChip(title: String(localized: "Paused"), icon: .pause, iconColor: VerbatimColor.orange)
        case .verifying:
            ModelStatusChip(title: String(localized: "Verifying"), icon: .loader, iconColor: VerbatimColor.orange)
        case .removing:
            ModelStatusChip(title: String(localized: "Removing"), icon: .loader, iconColor: VerbatimColor.orange)
        case .failed:
            ModelStatusChip(title: String(localized: "Failed"), icon: .alert, iconColor: VerbatimColor.orange)
        case .notInstalled where !row.isSupported:
            ModelStatusChip(
                title: String(localized: "Not Supported on This Mac"),
                icon: .circle,
                iconColor: VerbatimColor.tertiaryText,
                style: .outlined
            )
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
    private var progress: some View {
        switch row.state {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 4) {
                if let progress {
                    SettingsProgressBar(fraction: progress.fraction)
                    caption(SettingsFormat.downloadCaption(progress))
                        .monospacedDigit()
                } else {
                    IndeterminateProgressBar()
                    caption(String(localized: "Starting…"))
                }
            }
            .padding(.top, 5)
        case .waitingForRecording(let progress):
            VStack(alignment: .leading, spacing: 4) {
                SettingsProgressBar(fraction: progress?.fraction ?? 0, tint: VerbatimColor.orange)
                caption(String(localized: "Waiting for the recording to end."))
            }
            .padding(.top, 5)
        case .verifying:
            VStack(alignment: .leading, spacing: 4) {
                IndeterminateProgressBar()
                caption(String(localized: "Checking the downloaded files."))
            }
            .padding(.top, 5)
        case .failed(let failure):
            failureDescription(ModelIssue(failure))
                .padding(.top, 3)
        case .notInstalled, .installed, .removing:
            EmptyView()
        }
    }

    private func failureDescription(_ issue: ModelIssue) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(issue.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VerbatimColor.primaryText)
            caption(issue.message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(VerbatimColor.secondaryText)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            switch row.state {
            case .notInstalled:
                if row.isSupported {
                    DownloadButton { viewModel.download(row.id) }
                }
            case .downloading, .waitingForRecording, .verifying:
                Button {
                    viewModel.cancelDownload(row.id)
                } label: {
                    IconView(.xCircle, size: 16)
                }
                .buttonStyle(SettingsIconButtonStyle())
                .help("Cancel")
                .accessibilityLabel("Cancel \(row.model.name) download")
            case .installed:
                if !row.isSelected {
                    Button("Select") { viewModel.select(row.id) }
                        .buttonStyle(.verbatim(.secondary, size: .inline))
                }
                removeButton(help: "Remove model")
            case .failed(let failure):
                if failure != .unsupportedOnThisMac {
                    Button("Retry") { viewModel.download(row.id) }
                        .buttonStyle(.verbatim(.secondary, size: .inline))
                }
                removeButton(help: "Remove what was downloaded")
            case .removing:
                EmptyView()
            }
        }
        .fixedSize()
    }

    private func removeButton(help: LocalizedStringKey) -> some View {
        Button {
            viewModel.requestRemoval(of: row.id)
        } label: {
            IconView(.trash, size: 14)
        }
        .buttonStyle(SettingsIconButtonStyle())
        .help(help)
        .accessibilityLabel("Remove \(row.model.name)")
    }
}

/// The 22 pt Download button with an accent download icon.
struct DownloadButton: View {
    var title: LocalizedStringKey = "Download"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                IconView(.download, size: 12)
                    .foregroundStyle(VerbatimColor.accent)
                Text(title)
            }
        }
        .buttonStyle(.verbatim(.secondary, size: .inline))
    }
}
