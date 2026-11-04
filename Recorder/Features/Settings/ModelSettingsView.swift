import SwiftUI

/// The AI Models tab: its sections scroll inside a fixed height. Only reads state; it never performs file or network
/// work and never loads a model.
struct ModelSettingsView: View {
    @Bindable var viewModel: ModelSettingsViewModel

    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                speechRecognition
                semanticSearch
                processing
            }
            .padding(SettingsLayout.contentPadding)
        }
        .frame(height: SettingsLayout.modelsTabHeight)
        // Runs when the tab appears and again when the window comes forward, so files removed in Finder show up.
        .task(id: controlActiveState) {
            if controlActiveState != .inactive {
                await viewModel.refresh()
            }
        }
        .sheet(item: $viewModel.removalRequest) { request in
            RemoveModelSheet(
                request: request,
                cancel: viewModel.cancelRemoval,
                remove: viewModel.confirmRemoval
            )
        }
        .alert(
            viewModel.actionIssue?.title ?? "",
            isPresented: Binding(get: { viewModel.actionIssue != nil }, set: { _ in viewModel.dismissIssue() }),
            presenting: viewModel.actionIssue
        ) { _ in
            Button("OK", action: viewModel.dismissIssue)
        } message: { issue in
            Text(issue.message)
        }
    }

    // MARK: - Speech recognition

    private var speechRecognition: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Speech Recognition")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Text("Whisper · runs on this Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(VerbatimColor.secondaryText)
            }
            .padding(.horizontal, 2)

            if let notice = viewModel.notice {
                noticeCard(for: notice)
            }
            if let issue = viewModel.storageIssue {
                ModelNoticeCard(icon: .alert, title: issue.title, message: issue.message)
            }

            VStack(spacing: 0) {
                ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        VerbatimColor.separator
                            .frame(height: 0.5)
                            .padding(.horizontal, 12)
                    }
                    SpeechModelRow(row: row, viewModel: viewModel)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .groupedBackground()

            SettingsFootnote(text: footnote)
        }
    }

    private var footnote: String {
        let selection = String(
            localized: """
                The first model you download is selected automatically. Transcription will use the selected model once \
                it’s available. Selecting one doesn’t load it into memory. Models work offline once installed.
                """
        )
        guard viewModel.isCatalogOutdated else {
            return selection
        }
        return String(localized: "Couldn’t reach the model repository, so sizes may be out of date. \(selection)")
    }

    @ViewBuilder
    private func noticeCard(for notice: ModelSettingsViewModel.Notice) -> some View {
        switch notice {
        case .noModelInstalled(let recommended):
            ModelNoticeCard(
                icon: .sparkles,
                title: String(localized: "No speech model installed"),
                message: noModelMessage(recommended: recommended),
                actionTitle: recommended.map { "Download \($0.name)" },
                action: {
                    if let recommended {
                        viewModel.download(recommended.id)
                    }
                }
            )
        case .noModelSelected:
            ModelNoticeCard(
                icon: .info,
                title: String(localized: "No model selected"),
                message: String(localized: "Choose Select on an installed model.")
            )
        case .selectedModelUnavailable(let model):
            ModelNoticeCard(
                icon: .alert,
                title: String(localized: "“\(model.name)” isn’t available"),
                message: String(
                    localized: """
                        It’s still selected, but its files are missing or damaged. Download it again, or choose \
                        another installed model.
                        """
                ),
                actionTitle: "Repair",
                action: { viewModel.download(model.id) }
            )
        }
    }

    private func noModelMessage(recommended: SpeechModel?) -> String {
        guard let recommended else {
            return String(localized: "Download a model to use for transcription.")
        }
        return String(localized: "Nothing downloads until you ask. For this Mac, \(recommended.name) is a good start.")
    }

    // MARK: - Semantic search

    /// Embedding models aren't supported yet, so nothing here can be turned on or downloaded.
    private var semanticSearch: some View {
        SettingsSection(
            title: "Semantic Search",
            footnote: String(localized: "Until then, the Library searches recording titles and dates.")
        ) {
            SettingsRow(
                title: "Search by Meaning",
                detail: String(
                    localized:
                        "Not available yet: this version can’t install an embedding model or build a search index."
                )
            ) {
                ModelStatusChip(
                    title: String(localized: "Coming Later"),
                    icon: .circle,
                    iconColor: VerbatimColor.tertiaryText,
                    style: .outlined
                )
                .fixedSize()
            }
        }
    }

    // MARK: - Processing

    private var processing: some View {
        SettingsSection(title: "Processing") {
            pausedWhileRecording
            GroupedDivider(leadingInset: 12)
            SettingsRow(title: "Space Used by AI Models", isCompact: true) {
                Text(SettingsFormat.size(bytes: viewModel.storageUsageBytes))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(VerbatimColor.secondaryText)
                Button("Show in Finder", action: viewModel.showModelsInFinder)
                    .buttonStyle(.verbatim(.secondary, size: .inline))
            }
        }
    }

    private var pausedWhileRecording: some View {
        HStack(alignment: .top, spacing: 10) {
            IconView(.pause, size: 15)
                .foregroundStyle(VerbatimColor.secondaryText)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Paused While Recording")
                    .font(.system(size: 13))
                Text(
                    """
                    Model downloads and checks stop during a recording and continue when it ends, so capture stays \
                    smooth. This can’t be turned off.
                    """
                )
                .font(.system(size: 11))
                .lineSpacing(1.5)
                .foregroundStyle(VerbatimColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Something about the models as a whole that needs attention, with at most one action.
private struct ModelNoticeCard: View {
    let icon: VerbatimIcon
    let title: String
    let message: String
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IconView(icon, size: 15)
                .foregroundStyle(VerbatimColor.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .lineSpacing(1.5)
                    .foregroundStyle(VerbatimColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let actionTitle {
                DownloadButton(title: LocalizedStringKey(actionTitle), action: action)
                    .fixedSize()
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .groupedBackground()
    }
}
