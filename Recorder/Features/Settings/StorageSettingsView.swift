import SwiftUI

/// Where recordings are saved, how space is used, and cleanup actions that never touch original recordings.
struct StorageSettingsView: View {
    let viewModel: SettingsViewModel

    @State private var isChoosingFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            location
            diskUsage
            freeUpSpace
        }
        .padding(SettingsLayout.contentPadding)
        .fixedSize(horizontal: false, vertical: true)
        .task { await viewModel.refreshStorage() }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): viewModel.chooseRecordingsFolder(url)
            case .failure(let error): viewModel.folderSelectionFailed(error)
            }
        }
    }

    // MARK: - Location

    private var location: some View {
        SettingsSection(
            title: "Recordings Location",
            footnote: String(
                localized: """
                    New recordings go here, each in a folder of its own. Existing recordings stay where they are and \
                    remain in the Library.
                    """
            )
        ) {
            HStack(spacing: 10) {
                IconView(.folder, size: 22)
                    .foregroundStyle(VerbatimColor.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(folderName)
                        .font(.system(size: 13, weight: .medium))
                    Text(verbatim: folderPath)
                        .font(.system(size: 11))
                        .foregroundStyle(VerbatimColor.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button("Change…") { isChoosingFolder = true }
                    .buttonStyle(.verbatim(.secondary, size: .inline))
                Button("Show in Finder", action: viewModel.showRecordingsInFinder)
                    .buttonStyle(.verbatim(.secondary, size: .inline))
                    .disabled(viewModel.recordingsStorage == nil)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
    }

    private var folderPath: String {
        viewModel.recordingsStorage?.location.displayPath ?? ""
    }

    private var folderName: String {
        (folderPath as NSString).lastPathComponent
    }

    // MARK: - Disk usage

    private var diskUsage: some View {
        SettingsSection(title: "Disk Usage") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Verbatim uses \(SettingsFormat.size(bytes: viewModel.totalBytes))")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .fixedSize()
                    Spacer(minLength: 0)
                    if let storage = viewModel.recordingsStorage {
                        Text("\(SettingsFormat.freeSpace(storage.location.availableBytes)) available")
                            .font(.system(size: 11))
                            .foregroundStyle(VerbatimColor.secondaryText)
                    }
                }
                UsageBar(
                    recordingsBytes: viewModel.recordingsStorage?.usedBytes ?? 0,
                    modelsBytes: viewModel.modelsBytes
                )
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            GroupedDivider(leadingInset: 12)
            usageRow(color: VerbatimColor.accent, title: "Recordings", detail: recordingsDetail) {
                sizeText(viewModel.recordingsStorage?.usedBytes ?? 0)
            }
            GroupedDivider(leadingInset: 30)
            usageRow(color: VerbatimColor.purple, title: "AI Models", detail: modelsDetail) {
                sizeText(viewModel.modelsBytes)
                Button("Show in Finder", action: viewModel.models.showModelsInFinder)
                    .buttonStyle(.verbatim(.secondary, size: .inline))
            }
        }
    }

    private var recordingsDetail: String? {
        viewModel.recordingsStorage.map { String(localized: "\($0.recordingCount) recordings") }
    }

    private var modelsDetail: String {
        let installedCount = viewModel.models.rows.filter(\.state.isInstalled).count
        return String(localized: "\(installedCount) speech")
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

    private func sizeText(_ bytes: Int64) -> some View {
        Text(SettingsFormat.size(bytes: bytes))
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(VerbatimColor.secondaryText)
    }

    // MARK: - Free up space

    private var freeUpSpace: some View {
        VStack(alignment: .leading, spacing: 6) {
            let unusedModels = viewModel.models.unusedModels
            if !unusedModels.isEmpty {
                SettingsSection(title: "Free Up Space") {
                    SettingsRow(title: "Other Installed Models", detail: unusedModelsLine(unusedModels)) {
                        Button("Manage Models…", action: viewModel.showModels)
                            .buttonStyle(.verbatim(.secondary, size: .inline))
                    }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                IconView(.shield, size: 13)
                    .padding(.top, 1)
                Text(
                    """
                    Verbatim never deletes original recordings on its own. Removing a model leaves recordings and \
                    transcripts untouched, and deleting a recording from the Library moves it to the Trash.
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

    private func unusedModelsLine(_ rows: [ModelSettingsViewModel.Row]) -> String {
        let names = rows.map(\.model.name).joined(separator: ", ")
        let bytes = rows.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
        return String(localized: "\(names) · \(SettingsFormat.size(bytes: bytes))")
    }
}

/// Proportional bar of recordings and models, separated by a 1 pt gap.
private struct UsageBar: View {
    let recordingsBytes: Int64
    let modelsBytes: Int64

    var body: some View {
        GeometryReader { proxy in
            let total = max(Double(recordingsBytes + modelsBytes), 1)
            let width = proxy.size.width - 1
            HStack(spacing: 1) {
                VerbatimColor.accent
                    .frame(width: width * Double(recordingsBytes) / total)
                VerbatimColor.purple
                    .frame(width: width * Double(modelsBytes) / total)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .background(VerbatimColor.fill)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityHidden(true)
    }
}
