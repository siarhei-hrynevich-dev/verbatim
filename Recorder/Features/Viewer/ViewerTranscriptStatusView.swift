import SwiftUI

/// A real recording's transcript panel with no lines to show: how to get a transcript, how that is going, or why it
/// failed. Everything shown is the job's actual state. Playback works in every case.
struct ViewerTranscriptStatusView: View {
    let viewModel: ViewerViewModel
    let actions: ViewerWindowActions

    var body: some View {
        VStack(spacing: 10) {
            IconView(icon, size: 36)
                .foregroundStyle(iconColor)
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
            if case .running(let stage) = viewModel.transcriptActivity {
                ViewerTranscriptProgress(stage: stage)
            }
            Text(message)
                .font(.system(size: 12))
                .lineSpacing(4)
                .foregroundStyle(VerbatimColor.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
                .fixedSize(horizontal: false, vertical: true)
            buttons
                .padding(.top, 8)
        }
        .padding(.top, 24)
        .padding(.horizontal, 28)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 8) {
            switch viewModel.transcriptActivity {
            case .queued, .running:
                Button("Cancel Transcription", action: viewModel.cancelProcessing)
                    .buttonStyle(.verbatim(.secondary, size: .regular))
            case .stopping:
                EmptyView()
            case .failed(let issue):
                startButton
                if issue.recovery == .openSettings {
                    Button("Open Settings", action: actions.openSettings)
                        .buttonStyle(.verbatim(.secondary, size: .regular))
                }
            case nil:
                startButton
            }
        }
    }

    @ViewBuilder
    private var startButton: some View {
        if let title = viewModel.transcriptionActionTitle {
            Button(action: viewModel.startProcessing) {
                HStack(spacing: 6) {
                    IconView(viewModel.hasEmptyTranscript ? .retry : .file, size: 12)
                    Text(title)
                }
            }
            .buttonStyle(.verbatim(.accent, size: .regular))
        }
    }

    private var icon: VerbatimIcon {
        switch viewModel.transcriptActivity {
        case .queued, .running, .stopping: .loader
        case .failed: .alert
        case nil: .file
        }
    }

    private var iconColor: Color {
        switch viewModel.transcriptActivity {
        case .queued, .running, .stopping: VerbatimColor.accent
        case .failed: VerbatimColor.red
        case nil: VerbatimColor.tertiaryText
        }
    }

    private var title: String {
        switch viewModel.transcriptActivity {
        case .queued: String(localized: "Waiting to Transcribe")
        case .running: String(localized: "Transcribing on This Mac")
        case .stopping: String(localized: "Stopping…")
        case .failed(let issue): issue.title
        case nil: idleTitle
        }
    }

    private var idleTitle: String {
        if viewModel.hasEmptyTranscript {
            return String(localized: "No Speech Found")
        }
        return String(localized: "No Transcript Yet")
    }

    private var message: String {
        switch viewModel.transcriptActivity {
        case .queued:
            String(localized: "It starts after the work ahead of it, and waits while you’re recording.")
        case .running:
            String(localized: "The recording is saved and you can play it now. Lines appear here when this finishes.")
        case .stopping:
            String(localized: "The model is finishing its current step. The recording isn’t affected.")
        case .failed(let issue):
            issue.message
        case nil:
            idleMessage
        }
    }

    private var idleMessage: String {
        if viewModel.hasEmptyTranscript {
            return String(localized: "The selected model didn’t hear anything to write down.")
        }
        return String(
            localized: "Transcribe this recording with the model selected in Settings. Nothing leaves this Mac."
        )
    }
}

/// While a transcript is showing: a replacement being made, or a problem with the latest attempt. The lines stay put,
/// because the transcript is only replaced once the new one is complete.
struct ViewerTranscriptActivityBanner: View {
    let viewModel: ViewerViewModel
    let actions: ViewerWindowActions

    var body: some View {
        if let activity = viewModel.transcriptActivity {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(summary(of: activity))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isFailure(activity) ? VerbatimColor.red : VerbatimColor.primaryText)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    action(for: activity)
                }
                if case .running(let stage) = activity {
                    ViewerTranscriptProgress(stage: stage, showsStage: false)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        } else if let warning = viewModel.transcriptExportWarning {
            Text("The transcript is saved, but its files couldn’t be written beside the recording. \(warning)")
                .font(.system(size: 11))
                .foregroundStyle(VerbatimColor.secondaryText)
                .lineLimit(3)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func action(for activity: ViewerTranscriptActivity) -> some View {
        switch activity {
        case .queued, .running:
            Button("Cancel", action: viewModel.cancelProcessing)
                .buttonStyle(.verbatim(.secondary, size: .small))
                .fixedSize()
        case .failed:
            Button("Retry", action: viewModel.startProcessing)
                .buttonStyle(.verbatim(.secondary, size: .small))
                .fixedSize()
        case .stopping:
            EmptyView()
        }
    }

    private func isFailure(_ activity: ViewerTranscriptActivity) -> Bool {
        if case .failed = activity {
            return true
        }
        return false
    }

    private func summary(of activity: ViewerTranscriptActivity) -> String {
        switch activity {
        case .queued: String(localized: "A new transcript is waiting its turn. This one stays until it’s ready.")
        case .running: String(localized: "Making a new transcript. This one stays until it’s ready.")
        case .stopping: String(localized: "Stopping…")
        case .failed(let issue): String(localized: "\(issue.title). This transcript is unchanged.")
        }
    }
}

/// The stage of a running job, with a bar when there is a measurement to show. Nothing here is estimated.
private struct ViewerTranscriptProgress: View {
    let stage: ViewerTranscriptActivity.Stage
    var showsStage = true

    var body: some View {
        VStack(spacing: 6) {
            if let fraction {
                Capsule()
                    .fill(VerbatimColor.fill)
                    .frame(maxWidth: 260)
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(VerbatimColor.accent)
                                .frame(width: proxy.size.width * fraction)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Transcription progress")
                    .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
            }
            if showsStage {
                Text(label)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(VerbatimColor.secondaryText)
            }
        }
    }

    private var fraction: Double? {
        if case .processingAudio(let progress) = stage {
            return progress
        }
        return nil
    }

    private var label: String {
        switch stage {
        case .preparingModel:
            return String(localized: "Preparing model")
        case .processingAudio(let progress):
            guard let progress else {
                return String(localized: "Processing audio")
            }
            return String(localized: "Processing audio · \(Int((progress * 100).rounded()))%")
        case .savingTranscript:
            return String(localized: "Saving transcript")
        }
    }
}
