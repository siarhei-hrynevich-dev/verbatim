import SwiftUI

/// The AI Models tab: its sections scroll inside a fixed height. Only reads state; it never performs file or network
/// work and never loads a model.
struct ModelSettingsView: View {
    let speech: ModelSettingsViewModel<SpeechModel>
    @Bindable var summaries: SummarySettingsViewModel
    /// The language to transcribe in, which belongs to the preferences rather than to any model.
    @Binding var language: TranscriptionLanguage

    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ModelCatalogSection(viewModel: speech, texts: Self.speechTexts)
                ModelCatalogSection(viewModel: summaries.models, texts: Self.summaryTexts)
                SummarySettingsSection(viewModel: summaries)
                semanticSearch
                processing
            }
            .padding(SettingsLayout.contentPadding)
        }
        .frame(height: SettingsLayout.modelsTabHeight)
        // Runs when the tab appears and again when the window comes forward, so files removed in Finder show up.
        .task(id: controlActiveState) {
            if controlActiveState != .inactive {
                await speech.refresh()
                await summaries.models.refresh()
            }
        }
    }

    private static let speechTexts = ModelCatalogTexts(
        title: "Speech Recognition",
        subtitle: "Whisper · runs on this Mac",
        noModelTitle: String(localized: "No speech model installed"),
        purpose: String(localized: "Download a model to use for transcription."),
        footnote: String(
            localized: """
                The first model you download is selected automatically. Transcription will use the selected model \
                once it’s available. Selecting one doesn’t load it into memory. Models work offline once installed.
                """
        )
    )

    private static let summaryTexts = ModelCatalogTexts(
        title: "Summaries",
        subtitle: "MLX · runs on this Mac",
        noModelTitle: String(localized: "No summary model installed"),
        purpose: String(localized: "Download a model to summarize transcripts."),
        footnote: String(
            localized: """
                Summaries use the selected model. Long recordings are summarized in batches, then combined. The first \
                model you download is selected automatically, and models work offline once installed.
                """
        )
    )

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
            SettingsRow(
                title: "Transcription Language",
                detail: String(localized: "Automatic detection works for most recordings, including mixed languages.")
            ) {
                SettingsPopUpMenu(
                    accessibilityLabel: "Transcription Language",
                    selectionTitle: language.title,
                    selection: $language
                ) {
                    Text(TranscriptionLanguage.automatic.title).tag(TranscriptionLanguage.automatic)
                    ForEach(TranscriptionLanguage.choices, id: \.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
            }
            GroupedDivider(leadingInset: 12)
            SettingsRow(
                title: "Summary Language",
                detail: String(
                    localized: "Summaries are written in this language, whatever language the recording is in."
                )
            ) {
                SettingsPopUpMenu(
                    accessibilityLabel: "Summary Language",
                    selectionTitle: summaries.language.title,
                    selection: $summaries.language
                ) {
                    ForEach(SummaryLanguage.choices, id: \.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
            }
            GroupedDivider(leadingInset: 12)
            pausedWhileRecording
            GroupedDivider(leadingInset: 12)
            SettingsRow(title: "Space Used by AI Models", isCompact: true) {
                Text(SettingsFormat.size(bytes: speech.storageUsageBytes + summaries.models.storageUsageBytes))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(VerbatimColor.secondaryText)
                Button("Show in Finder", action: speech.showModelsInFinder)
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
                    Model downloads, checks, transcription and summaries stop during a recording and continue when \
                    it ends, so capture stays smooth. This can’t be turned off.
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
