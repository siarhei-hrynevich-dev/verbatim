import AppKit
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
                AudioSourcesSection(viewModel: viewModel, selection: viewModel.selection)
                RecordingOptionsSection(viewModel: viewModel)
            }
            .disabled(viewModel.phase != .ready)
            .padding(.horizontal, RecorderLayout.horizontalPadding)
            .padding(.top, 4)

            Spacer(minLength: 0)

            footer
        }
        .onAppear { viewModel.setSetupVisible(NSApp.isActive) }
        // Shows real sources even when the app opened in the background.
        .task { await viewModel.refresh() }
        .onDisappear { viewModel.setSetupVisible(false) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.setSetupVisible(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            viewModel.setSetupVisible(false)
        }
        .fileImporter(isPresented: $viewModel.isChoosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): viewModel.chooseFolder(url)
            case .failure(let error): viewModel.folderSelectionFailed(error)
            }
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
            if let savedRecordingTitle = viewModel.savedRecordingTitle {
                savedNotice(title: savedRecordingTitle)
            }

            Button {
                viewModel.startRecording()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.white)
                        .frame(width: 11, height: 11)
                    Text(viewModel.phase == .preparing ? "Preparing…" : "Start Recording")
                }
            }
            .buttonStyle(.verbatim(.record, size: .large))
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!viewModel.canStartRecording)

            HStack(spacing: 6) {
                folderButton
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

    /// Opens the recordings folder in Finder; its context menu changes the folder.
    private var folderButton: some View {
        Button(action: viewModel.openRecordingsFolder) {
            HStack(spacing: 6) {
                IconView(.folder, size: 12)
                Text(viewModel.storageSummary)
            }
        }
        .buttonStyle(.plain)
        .help("Show in Finder")
        .contextMenu {
            Button("Choose Folder…") {
                viewModel.isChoosingFolder = true
            }
            Button("Use Default Location", action: viewModel.useDefaultFolder)
        }
    }

    private func savedNotice(title: String) -> some View {
        HStack(spacing: 8) {
            IconView(.check, size: 14)
                .foregroundStyle(VerbatimColor.green)
            Text("Saved “\(title)”")
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
