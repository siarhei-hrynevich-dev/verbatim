import SwiftUI

/// The Ready state: last-used capture settings, an optional callout, and the Start Recording action.
struct RecorderSetupView: View {
    @Bindable var viewModel: RecorderViewModel
    let showLibrary: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: RecorderLayout.sectionSpacing) {
                if let issue = viewModel.issue {
                    issueBanner(issue)
                }
                SegmentedControl(
                    accessibilityLabel: "Capture source",
                    segments: [
                        .init(value: CaptureMode.screen, title: "Screen", icon: .monitor),
                        .init(value: CaptureMode.window, title: "Window", icon: .window),
                        .init(value: CaptureMode.audioOnly, title: "Audio Only", icon: .audio)
                    ],
                    selection: $viewModel.captureMode
                )
                CaptureSourcePicker(viewModel: viewModel)
                AudioSourcesSection(viewModel: viewModel)
                RecordingOptionsSection(viewModel: viewModel)
            }
            .padding(.horizontal, RecorderLayout.horizontalPadding)
            .padding(.top, 4)

            Spacer(minLength: 0)

            footer
        }
    }

    private func issueBanner(_ issue: RecorderIssue) -> some View {
        CalloutBanner(
            icon: issue.icon,
            title: issue.title,
            message: issue.message,
            primaryAction: .init(title: issue.primaryActionTitle, perform: viewModel.performIssuePrimaryAction),
            secondaryAction: .init(title: issue.secondaryActionTitle, perform: viewModel.performIssueSecondaryAction)
        )
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if viewModel.hasSavedRecording {
                savedNotice
            }

            Button {
                viewModel.startRecording()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.white)
                        .frame(width: 11, height: 11)
                    Text("Start Recording")
                }
            }
            .buttonStyle(.verbatim(.record, size: .large))
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!viewModel.canStartRecording)

            HStack(spacing: 6) {
                IconView(.folder, size: 12)
                Text(viewModel.sources.storageSummary)
                Spacer(minLength: 0)
                Text("⌘⇧R")
                    .accessibilityHidden(true)
            }
            .font(.system(size: 11))
            .foregroundStyle(VerbatimColor.secondaryText)
        }
        .padding(.horizontal, RecorderLayout.horizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    private var savedNotice: some View {
        HStack(spacing: 8) {
            IconView(.check, size: 14)
                .foregroundStyle(VerbatimColor.green)
            Text("Saved “\(viewModel.sources.savedRecordingTitle)” · transcription queued")
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Show in Library", action: showLibrary)
                .buttonStyle(LinkButtonStyle())
        }
        .font(.system(size: 12))
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(VerbatimColor.groupBackground, in: RoundedRectangle(cornerRadius: 8))
        .hairlineBorder(cornerRadius: 8)
    }
}

/// An inline text action in the accent color.
private struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .foregroundStyle(VerbatimColor.accent)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .focusRing(cornerRadius: 3)
    }
}
