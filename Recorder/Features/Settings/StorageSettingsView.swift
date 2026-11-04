import SwiftUI

/// Where recordings are saved, how space is used, and cleanup actions that never touch original recordings.
struct StorageSettingsView: View {
    let viewModel: SettingsViewModel
    let actions: SettingsWindowActions

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            location
            diskUsage
            freeUpSpace
        }
        .padding(SettingsLayout.contentPadding)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Location

    private var location: some View {
        let location = viewModel.location
        return SettingsSection(
            title: "Recordings Location",
            footnote: String(
                localized: "Each recording is a folder holding the video or audio tracks, transcript and metadata."
            )
        ) {
            HStack(spacing: 10) {
                IconView(.folder, size: 22)
                    .foregroundStyle(VerbatimColor.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(location.folderName)
                        .font(.system(size: 13, weight: .medium))
                    Text(verbatim: "\(location.path) · \(location.volumeName)")
                        .font(.system(size: 11))
                        .foregroundStyle(VerbatimColor.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button("Change…", action: viewModel.requestLocationChange)
                    .buttonStyle(.verbatim(.secondary, size: .inline))
                Button("Show in Finder", action: actions.showRecordingsInFinder)
                    .buttonStyle(.verbatim(.secondary, size: .inline))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Disk usage

    private var diskUsage: some View {
        SettingsSection(title: "Disk Usage") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Verbatim uses \(SettingsFormat.size(megabytes: viewModel.totalMegabytes))")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .fixedSize()
                    Spacer(minLength: 0)
                    Text(freeSpaceLine)
                        .font(.system(size: 11))
                        .foregroundStyle(VerbatimColor.secondaryText)
                }
                UsageBar(viewModel: viewModel)
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            GroupedDivider(leadingInset: 12)
            usageRow(color: VerbatimColor.accent, title: "Recordings", detail: recordingsDetail) {
                sizeText(viewModel.data.recordingsMegabytes)
            }
            GroupedDivider(leadingInset: 30)
            usageRow(color: VerbatimColor.purple, title: "AI Models", detail: modelsDetail) {
                sizeText(viewModel.modelsMegabytes)
                Button("Show in Finder", action: actions.showModelsInFinder)
                    .buttonStyle(.verbatim(.secondary, size: .inline))
            }
            GroupedDivider(leadingInset: 30)
            usageRow(color: VerbatimColor.orange, title: "Search Index and Cache", detail: nil) {
                sizeText(viewModel.cacheMegabytes)
            }
        }
    }

    private var freeSpaceLine: String {
        let location = viewModel.location
        return String(localized: "\(SettingsFormat.freeSpace(location.freeBytes)) available on \(location.volumeName)")
    }

    private var recordingsDetail: String {
        String(localized: "\(viewModel.data.recordingCount) recordings")
    }

    private var modelsDetail: String {
        let speechCount = viewModel.installedSpeechModels.count
        let embeddingCount = viewModel.embeddingState.isInstalled ? 1 : 0
        return String(localized: "\(speechCount) speech, \(embeddingCount) embedding")
    }

    private func usageRow(
        color: Color,
        title: LocalizedStringKey,
        detail: String?,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            HStack(spacing: 4) {
                Text(title)
                if let detail {
                    Text(verbatim: "· \(detail)")
                        .foregroundStyle(VerbatimColor.secondaryText)
                }
            }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    private func sizeText(_ megabytes: Int) -> some View {
        Text(SettingsFormat.size(megabytes: megabytes))
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(VerbatimColor.secondaryText)
    }

    // MARK: - Free up space

    private var freeUpSpace: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsSection(title: "Free Up Space") {
                SettingsRow(title: "Preview Cache", detail: cacheLine) {
                    Button("Clear Cache", action: viewModel.clearPreviewCache)
                        .buttonStyle(.verbatim(.secondary, size: .inline))
                        .disabled(viewModel.previewCacheMegabytes == 0)
                }
                if let model = viewModel.unusedSpeechModel {
                    GroupedDivider(leadingInset: 12)
                    SettingsRow(title: "Unused Speech Model", detail: unusedModelLine(model)) {
                        Button("Manage Models…", action: viewModel.showModels)
                            .buttonStyle(.verbatim(.secondary, size: .inline))
                    }
                }
                GroupedDivider(leadingInset: 12)
                SettingsRow(title: "Missing Recordings", detail: missingLine) {
                    Button("Review in Library…", action: actions.reviewMissingRecordings)
                        .buttonStyle(.verbatim(.secondary, size: .inline))
                }
            }
            HStack(alignment: .top, spacing: 8) {
                IconView(.shield, size: 13)
                    .padding(.top, 1)
                Text(
                    """
                    Verbatim never deletes original recordings on its own. Clearing the cache leaves recordings and \
                    transcripts untouched, and deleting a recording from the Library moves its folder to the Trash.
                    """
                )
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11))
            .foregroundStyle(VerbatimColor.secondaryText)
            .padding(.top, 2)
            .padding(.horizontal, 12)
        }
    }

    private var cacheLine: String {
        let cache = viewModel.previewCacheMegabytes
        guard cache > 0 else {
            return String(localized: "Cleared. Thumbnails and waveforms are recreated as you browse.")
        }
        return String(localized: "Thumbnails and waveforms · \(cache) MB · rebuilt when needed")
    }

    private func unusedModelLine(_ model: SpeechModel) -> String {
        let size = SettingsFormat.size(megabytes: model.sizeMegabytes)
        return String(localized: "\(model.name) · \(size) · not used in the last 30 days")
    }

    private var missingLine: String {
        let count = viewModel.data.missingRecordingCount
        return String(localized: "\(count) Library entries point to folders that are no longer there.")
    }
}

/// Proportional bar of recordings, models and cache, separated by 1 pt gaps.
private struct UsageBar: View {
    let viewModel: SettingsViewModel

    var body: some View {
        GeometryReader { proxy in
            let total = max(Double(viewModel.totalMegabytes), 1)
            let width = proxy.size.width - 2
            HStack(spacing: 1) {
                VerbatimColor.accent
                    .frame(width: width * Double(viewModel.data.recordingsMegabytes) / total)
                VerbatimColor.purple
                    .frame(width: width * Double(viewModel.modelsMegabytes) / total)
                VerbatimColor.orange
                    .frame(width: max(3, width * Double(viewModel.cacheMegabytes) / total))
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .background(VerbatimColor.fill)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityHidden(true)
    }
}
