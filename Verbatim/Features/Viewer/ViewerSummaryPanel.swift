import SwiftUI

/// The side panel's summary: the summary itself, then the notes on each part of the recording, each of which seeks to
/// where that part begins. Without a summary it shows what is happening, or what is needed first.
struct ViewerSummaryPanel: View {
    let viewModel: ViewerViewModel
    let actions: ViewerWindowActions

    var body: some View {
        VStack(spacing: 0) {
            header
            if let activity = viewModel.summaryActivity {
                activityBanner(activity)
            }
            if let summary = viewModel.summary {
                content(summary)
            } else {
                emptyState
            }
        }
        .background(VerbatimColor.transcriptBackground)
        .task(id: viewModel.summaries?.revision) { await viewModel.reloadSummaryIfNeeded() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Summary")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Summary")
                .font(.system(size: 13, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            if let summary = viewModel.summary {
                Text("\(summary.parts.count) parts")
                    .font(.system(size: 11))
                    .foregroundStyle(VerbatimColor.secondaryText)
            }
            Spacer(minLength: 0)
            Button(action: copySummary) {
                IconView(.copy, size: 14)
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(PanelIconButtonStyle())
            .disabled(viewModel.summary == nil)
            .help("Copy Summary")
            .accessibilityLabel("Copy Summary")
        }
        .padding(.top, 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Summary

    private func content(_ summary: TranscriptSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let staleness = viewModel.summaryStaleness, viewModel.summaryActivity == nil {
                    note(
                        staleness,
                        actionTitle: viewModel.summaryActionTitle,
                        action: viewModel.generateSummary
                    )
                }
                Text(Self.markdown(summary.text))
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Parts")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VerbatimColor.secondaryText)
                    .padding(.top, 4)
                ForEach(summary.parts, id: \.position) { part in
                    partRow(part)
                }
                if viewModel.summaryActivity == nil, viewModel.canSummarize {
                    Button(viewModel.summaryActionTitle, action: viewModel.generateSummary)
                        .buttonStyle(.verbatim(.secondary, size: .inline))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    private func partRow(_ part: SummaryPart) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                viewModel.seek(toPart: part)
            } label: {
                Text("\(RecordingClock.timerText(for: part.startTime))–\(RecordingClock.timerText(for: part.endTime))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(VerbatimColor.accent)
            }
            .buttonStyle(.plain)
            .help("Play from Here")
            Text(Self.markdown(part.text))
                .font(.system(size: 12))
                .lineSpacing(2)
                .foregroundStyle(VerbatimColor.secondaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - States

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            IconView(.sparkles, size: 22)
                .foregroundStyle(VerbatimColor.tertiaryText)
            if viewModel.canSummarize {
                Text("No summary yet")
                    .font(.system(size: 13, weight: .semibold))
                Text("A language model on this Mac reads the transcript in batches and sums it up.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 12))
                    .foregroundStyle(VerbatimColor.secondaryText)
                if viewModel.summaryActivity == nil {
                    Button(viewModel.summaryActionTitle, action: viewModel.generateSummary)
                        .buttonStyle(.verbatim(.accent, size: .inline))
                }
            } else {
                Text("Summaries need a transcript")
                    .font(.system(size: 13, weight: .semibold))
                Text("Generate the transcript first; the summary is made from it.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 12))
                    .foregroundStyle(VerbatimColor.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func activityBanner(_ activity: ViewerSummaryActivity) -> some View {
        switch activity {
        case .failed(let issue):
            VStack(alignment: .leading, spacing: 6) {
                Text(issue.title)
                    .font(.system(size: 12, weight: .semibold))
                Text(issue.message)
                    .font(.system(size: 11))
                    .foregroundStyle(VerbatimColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if issue.needsSettings {
                        Button("Open Settings", action: actions.openSettings)
                            .buttonStyle(.verbatim(.secondary, size: .inline))
                    }
                    if viewModel.canSummarize {
                        Button("Try Again", action: viewModel.generateSummary)
                            .buttonStyle(.verbatim(.secondary, size: .inline))
                    }
                    Button("Dismiss", action: viewModel.dismissSummaryFailure)
                        .buttonStyle(.verbatim(.secondary, size: .inline))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .groupedBackground()
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        default:
            note(Self.progressText(activity), actionTitle: String(localized: "Cancel"), action: viewModel.cancelSummary)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
    }

    private func note(_ text: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(VerbatimColor.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(actionTitle, action: action)
                .buttonStyle(.verbatim(.secondary, size: .inline))
        }
        .padding(10)
        .groupedBackground()
    }

    private static func progressText(_ activity: ViewerSummaryActivity) -> String {
        switch activity {
        case .queued: String(localized: "Waiting to summarize…")
        case .loadingModel: String(localized: "Loading the model…")
        case .writingParts(let completed, let total): String(localized: "Reading part \(completed + 1) of \(total)…")
        case .combining: String(localized: "Writing the summary…")
        case .saving: String(localized: "Saving…")
        case .stopping: String(localized: "Stopping…")
        case .failed(let issue): issue.title
        }
    }

    /// Models write Markdown; inline styles render, and line breaks stay as written.
    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private func copySummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.summaryText, forType: .string)
    }
}

/// Chooses between the transcript and its summary above the side panel. Shown only for real recordings.
struct ViewerPanelModePicker: View {
    @Bindable var viewModel: ViewerViewModel

    var body: some View {
        SegmentedControl(
            accessibilityLabel: "Side Panel",
            segments: [
                .init(value: ViewerPanelMode.transcript, title: "Transcript"),
                .init(value: ViewerPanelMode.summary, title: "Summary")
            ],
            selection: $viewModel.panelMode
        )
        .padding(.top, 12)
        .padding(.horizontal, 14)
    }
}

/// The transcript, or its summary when summaries are available for real recordings.
struct ViewerSidePanel: View {
    let viewModel: ViewerViewModel
    let actions: ViewerWindowActions

    var body: some View {
        if viewModel.isPreviewing || viewModel.summaries == nil {
            ViewerTranscriptPanel(viewModel: viewModel, actions: actions)
        } else {
            VStack(spacing: 0) {
                ViewerPanelModePicker(viewModel: viewModel)
                switch viewModel.panelMode {
                case .transcript:
                    ViewerTranscriptPanel(viewModel: viewModel, actions: actions)
                case .summary:
                    ViewerSummaryPanel(viewModel: viewModel, actions: actions)
                }
            }
            .background(VerbatimColor.transcriptBackground)
        }
    }
}
