import SwiftUI

/// The AI Models tab: its sections scroll inside the design's fixed height.
struct ModelsSettingsView: View {
    let viewModel: SettingsViewModel
    let showModelsInFinder: () -> Void

    var body: some View {
        ScrollView {
            ModelsSettingsContent(viewModel: viewModel, showModelsInFinder: showModelsInFinder)
        }
        .frame(height: SettingsLayout.modelsTabHeight)
    }
}

/// Speech recognition models, semantic search, and processing preferences.
struct ModelsSettingsContent: View {
    @Bindable var viewModel: SettingsViewModel
    let showModelsInFinder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            speechRecognition
            semanticSearch
            processing
        }
        .padding(SettingsLayout.contentPadding)
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

            VStack(spacing: 0) {
                ForEach(Array(viewModel.data.speechModels.enumerated()), id: \.element.id) { index, model in
                    if index > 0 {
                        VerbatimColor.separator
                            .frame(height: 0.5)
                            .padding(.horizontal, 12)
                    }
                    SpeechModelRow(model: model, viewModel: viewModel)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .groupedBackground()

            SettingsFootnote(
                text: String(
                    localized: """
                        New recordings use the default model. Existing transcripts are kept when you change it. \
                        The default can’t be removed until you pick another.
                        """
                )
            )
        }
    }

    // MARK: - Semantic search

    private var semanticSearch: some View {
        SettingsSection(
            title: "Semantic Search",
            footnote: String(
                localized: """
                    With semantic search off, the Library still matches exact words in titles and transcripts. \
                    Rebuilding re-reads every transcript; recordings are not modified.
                    """
            )
        ) {
            SettingsToggleRow(
                title: "Search by Meaning",
                detail: String(localized: "Finds moments that match an idea, even when the exact words differ."),
                isOn: $viewModel.isSemanticSearchEnabled
            )
            GroupedDivider(leadingInset: 12)
            VStack(spacing: 0) {
                EmbeddingModelRow(viewModel: viewModel)
                GroupedDivider(leadingInset: 12)
                searchIndexRow
            }
            .opacity(viewModel.isSemanticSearchEnabled ? 1 : 0.45)
        }
    }

    private var searchIndexRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Search Index")
                        .font(.system(size: 13))
                    if viewModel.indexStatus == .upToDate {
                        IconView(.check, size: 12)
                            .foregroundStyle(VerbatimColor.green)
                    }
                }
                Text(indexLine)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(VerbatimColor.secondaryText)
                if case .indexing(let indexed, let total) = viewModel.indexStatus {
                    SettingsProgressBar(fraction: Double(indexed) / Double(total))
                        .padding(.top, 4)
                        .animation(.easeOut(duration: 0.3), value: indexed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button("Rebuild Search Index", action: viewModel.rebuildSearchIndex)
                .buttonStyle(.verbatim(.secondary, size: .inline))
                .disabled(!viewModel.isSearchIndexAvailable)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
    }

    private var indexLine: String {
        switch viewModel.indexStatus {
        case .off:
            String(localized: "Off")
        case .waitingForModel:
            String(localized: "Waiting for the embedding model")
        case .indexing(let indexed, let total):
            String(localized: "Indexing \(indexed) of \(total) recordings…")
        case .upToDate:
            String(
                localized: """
                    Up to date · \(viewModel.data.recordingCount) recordings · \
                    \(SettingsFormat.size(megabytes: viewModel.data.searchIndexMegabytes))
                    """
            )
        }
    }

    // MARK: - Processing

    private var processing: some View {
        SettingsSection(title: "Processing") {
            SettingsRow(title: "Transcription Language", isCompact: true) {
                SettingsPopUpMenu(
                    accessibilityLabel: "Transcription Language",
                    selectionTitle: viewModel.language.name,
                    selection: $viewModel.language
                ) {
                    ForEach(Array(viewModel.data.languages.enumerated()), id: \.element.id) { index, language in
                        if index == 1 {
                            Divider()
                        }
                        Text(language.name).tag(language)
                    }
                }
            }
            GroupedDivider(leadingInset: 12)
            SettingsToggleRow(
                title: "Postpone on Battery Power",
                detail: String(localized: "Transcription and indexing wait until your Mac is connected to power."),
                isOn: $viewModel.postponesOnBattery
            )
            GroupedDivider(leadingInset: 12)
            pausedWhileRecording
            GroupedDivider(leadingInset: 12)
            SettingsRow(title: "Space Used by AI Models", isCompact: true) {
                Text(SettingsFormat.size(megabytes: viewModel.modelsMegabytes))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(VerbatimColor.secondaryText)
                Button("Show in Finder", action: showModelsInFinder)
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
                    Processing always stops during a recording and resumes when it ends, so capture stays smooth. \
                    This can’t be turned off.
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

/// The embedding model used by semantic search, with its download and remove actions.
private struct EmbeddingModelRow: View {
    let viewModel: SettingsViewModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Embedding Model")
                        .font(.system(size: 13))
                    chip
                }
                Text(viewModel.data.embeddingModelSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(VerbatimColor.secondaryText)
                if case .downloading(let progress) = viewModel.embeddingState {
                    SettingsProgressBar(fraction: progress)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
    }

    @ViewBuilder
    private var chip: some View {
        switch viewModel.embeddingState {
        case .installed, .preparing:
            ModelStatusChip(title: String(localized: "Installed"), icon: .check, iconColor: VerbatimColor.green)
        case .downloading(let progress):
            ModelStatusChip(
                title: String(localized: "Downloading \(Int((progress * 100).rounded()))%"),
                icon: .download,
                iconColor: VerbatimColor.accent
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
    private var actions: some View {
        switch viewModel.embeddingState {
        case .notInstalled:
            DownloadButton(action: viewModel.downloadEmbeddingModel)
                .disabled(!viewModel.isSemanticSearchEnabled)
        case .downloading, .preparing:
            Button(action: viewModel.cancelEmbeddingDownload) {
                IconView(.xCircle, size: 16)
            }
            .buttonStyle(SettingsIconButtonStyle())
            .accessibilityLabel("Cancel embedding model download")
        case .installed:
            Button("Remove", action: viewModel.removeEmbeddingModel)
                .buttonStyle(.verbatim(.secondary, size: .inline))
                .disabled(!viewModel.isSemanticSearchEnabled)
        }
    }
}
