import SwiftUI

/// The transcript panel before a transcript exists: processing with progress, failed with Retry, or not
/// processed with Generate Transcript. Playback works in every case.
struct ViewerTranscriptEmptyState: View {
    let viewModel: ViewerViewModel
    let actions: ViewerWindowActions

    var body: some View {
        VStack(spacing: 10) {
            IconView(icon, size: 36)
                .foregroundStyle(iconColor)
            Text("Transcript Not Available Yet")
                .font(.system(size: 15, weight: .bold))
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
            Text(status)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(statusColor)
            if case .processing(let progress) = state {
                progressDetails(progress)
            }
            Text(message)
                .font(.system(size: 12))
                .lineSpacing(4)
                .foregroundStyle(VerbatimColor.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(action: primaryAction) {
                    HStack(spacing: 6) {
                        IconView(primaryIcon, size: 12)
                        Text(primaryTitle)
                    }
                }
                .buttonStyle(.verbatim(.accent, size: .regular))
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.verbatim(.secondary, size: .regular))
            }
            .padding(.top, 8)
        }
        .padding(.top, 24)
        .padding(.horizontal, 28)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var state: ViewerRecording.TranscriptState {
        viewModel.recording.transcriptState
    }

    private func progressDetails(_ progress: Double) -> some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(VerbatimColor.fill)
                .frame(maxWidth: 260)
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(VerbatimColor.accent)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .padding(.top, 4)
                .accessibilityElement()
                .accessibilityLabel("Transcription progress")
                .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
            Text("Step 1 of 2 · Transcribing, then indexing · \(Int(progress * 100))% · about 3 min left")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(VerbatimColor.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private var icon: VerbatimIcon {
        switch state {
        case .processing, .ready: .loader
        case .failed: .alert
        case .notProcessed: .file
        }
    }

    private var iconColor: Color {
        switch state {
        case .processing, .ready: VerbatimColor.accent
        case .failed: VerbatimColor.red
        case .notProcessed: VerbatimColor.tertiaryText
        }
    }

    private var status: String {
        switch state {
        case .processing, .ready:
            String(localized: "Transcribing on this Mac")
        case .failed(let position):
            String(localized: "Transcription failed at \(RecordingClock.timerText(for: position))")
        case .notProcessed:
            String(localized: "Not processed")
        }
    }

    private var statusColor: Color {
        switch state {
        case .processing, .ready: VerbatimColor.primaryText
        case .failed: VerbatimColor.red
        case .notProcessed: VerbatimColor.secondaryText
        }
    }

    private var message: String {
        switch state {
        case .processing, .ready:
            String(
                localized: """
                    The recording is saved and you can play it now. Lines will appear here when processing finishes.
                    """
            )
        case .failed:
            String(
                localized: """
                    The audio track couldn’t be decoded past this point. The recording itself is intact and plays \
                    normally.
                    """
            )
        case .notProcessed:
            notProcessedMessage
        }
    }

    /// The estimate assumes transcription runs about nine times faster than real time on this Mac.
    private var notProcessedMessage: String {
        let minutes = Int(viewModel.duration / 60)
        let estimate = max(1, Int((Double(minutes) / 9).rounded()))
        return String(
            localized: """
                Automatic transcription was off when this was recorded. Generating a transcript for \(minutes) minutes \
                takes about \(estimate) minutes on this Mac.
                """
        )
    }

    private var primaryIcon: VerbatimIcon {
        switch state {
        case .processing, .ready: .pause
        case .failed: .retry
        case .notProcessed: .file
        }
    }

    private var primaryTitle: String {
        switch state {
        case .processing, .ready: String(localized: "Pause Processing")
        case .failed: String(localized: "Retry Processing")
        case .notProcessed: String(localized: "Generate Transcript")
        }
    }

    private var secondaryTitle: String {
        switch state {
        case .processing, .ready: String(localized: "Show in Library")
        case .failed: String(localized: "Show Log")
        case .notProcessed: String(localized: "Language: Auto-detect")
        }
    }

    private func primaryAction() {
        switch state {
        case .processing, .ready: actions.pauseProcessing()
        case .failed, .notProcessed: viewModel.startProcessing()
        }
    }

    private func secondaryAction() {
        switch state {
        case .processing, .ready: actions.backToLibrary()
        case .failed: actions.showLog()
        case .notProcessed: actions.chooseLanguage()
        }
    }
}
