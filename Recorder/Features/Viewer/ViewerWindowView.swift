import SwiftUI
import UniformTypeIdentifiers

/// The Viewer window: the player with a floating control HUD on the left, a resizable transcript panel on the
/// right, and the recording's title and file actions in the toolbar.
struct ViewerWindowView: View {
    static let windowID = "viewer"

    @Bindable var viewModel: ViewerViewModel
    /// Overrides the system accent color; `nil` follows the system.
    var accent: VerbatimAccent?
    var actions = ViewerWindowActions()
    /// Renders a real recording's video, supplied by App so this feature needs no knowledge of the player behind it.
    var videoSurface: AnyView?

    @Environment(\.dismissWindow) private var dismissWindow
    @State private var transcriptWidth = ViewerLayout.defaultTranscriptWidth

    var body: some View {
        HStack(spacing: 0) {
            ViewerPlayerView(viewModel: viewModel, videoSurface: videoSurface, backToLibrary: backToLibrary)
                .frame(minWidth: ViewerLayout.minimumPlayerWidth)
            if viewModel.recording != nil {
                TranscriptResizeHandle(width: $transcriptWidth)
                ViewerTranscriptPanel(viewModel: viewModel, actions: panelActions)
                    .frame(width: transcriptWidth)
            }
        }
        .foregroundStyle(VerbatimColor.primaryText)
        .background(VerbatimColor.windowBackground)
        .focusEffectDisabled()
        .navigationTitle(viewModel.title.isEmpty ? String(localized: "Viewer") : viewModel.title)
        .toolbar { toolbarContent }
        .task(id: viewModel.isPlaying) { await runSimulatedClock() }
        // Follows renames and removals made in the Library while this recording is open.
        .task(id: viewModel.libraryRevision) { await viewModel.refreshMetadata() }
        .fileExporter(
            isPresented: exportBinding,
            document: viewModel.exportDocument,
            contentType: viewModel.exportRequest?.contentType ?? .plainText,
            defaultFilename: viewModel.exportFileName
        ) { result in
            viewModel.finishExport(result)
        }
        .fileImporter(isPresented: $viewModel.isLocatingFile, allowedContentTypes: [.movie, .audio]) { result in
            viewModel.finishLocating(result)
        }
        .alert(
            viewModel.actionIssue?.title ?? "",
            isPresented: actionIssueBinding,
            presenting: viewModel.actionIssue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { issue in
            Text(issue.message)
        }
        // Nothing may keep playing, or keep the file open, in a window that is gone.
        .onDisappear(perform: viewModel.windowClosed)
        .verbatimAccent(accent)
    }

    /// Advances a design scenario's playback; the task is cancelled when playback stops or the window closes.
    private func runSimulatedClock() async {
        while viewModel.isPreviewing, viewModel.isPlaying, !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(ViewerLayout.clockTick))
            } catch {
                return
            }
            viewModel.advanceSimulation(by: ViewerLayout.clockTick)
        }
    }

    /// This window is one step on from the Library, so going back closes it, which also ends playback.
    private func backToLibrary() {
        actions.backToLibrary()
        dismissWindow(id: Self.windowID)
    }

    private var panelActions: ViewerWindowActions {
        var panelActions = actions
        panelActions.backToLibrary = backToLibrary
        panelActions.copyTranscript = copyTranscript
        panelActions.exportTranscript = { viewModel.requestExport($0) }
        return panelActions
    }

    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.transcriptText, forType: .string)
    }

    private var exportBinding: Binding<Bool> {
        Binding(
            get: { viewModel.exportRequest != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.exportRequest = nil
                }
            }
        )
    }

    private var actionIssueBinding: Binding<Bool> {
        Binding(
            get: { viewModel.actionIssue != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissActionIssue()
                }
            }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 6) {
                Button(action: backToLibrary) {
                    IconView(.chevronLeft, size: 16)
                        .frame(width: 30)
                }
                .buttonStyle(.toolbarIcon)
                .help("Back to Recordings")
                .accessibilityLabel("Back to Recordings")
                .keyboardShortcut("[", modifiers: .command)

                VStack(alignment: .leading, spacing: 0) {
                    RecordingTitleField(title: $viewModel.title, commit: viewModel.commitTitle)
                        .disabled(viewModel.recording == nil)
                    Text(metadata)
                        .font(.system(size: 11))
                        .foregroundStyle(VerbatimColor.secondaryText)
                        .lineLimit(1)
                }
            }
            .fixedSize()
        }

        ToolbarItemGroup(placement: .primaryAction) {
            fileActions
            moreActions
        }
    }

    /// Show in Finder and the Export menu, joined in one bordered control.
    private var fileActions: some View {
        HStack(spacing: 0) {
            Button(action: viewModel.showInFinder) {
                HStack(spacing: 6) {
                    IconView(.folder, size: 14)
                    Text("Show in Finder")
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
            }
            .buttonStyle(SegmentPartButtonStyle(edges: .leading))
            .help("Show in Finder")

            VerbatimColor.separator.frame(width: 0.5, height: 26)

            ViewerExportMenu(
                hasTranscript: viewModel.recording?.hasTranscript ?? false,
                canShowTranscriptInFinder: viewModel.canShowTranscriptInFinder,
                showTranscriptInFinder: viewModel.showTranscriptInFinder,
                actions: panelActions
            )
        }
        .disabled(viewModel.recording == nil)
        .font(.system(size: 12))
        .foregroundStyle(VerbatimColor.primaryText)
        .background(VerbatimColor.controlBackground, in: RoundedRectangle(cornerRadius: 7))
        .hairlineBorder(cornerRadius: 7)
        .shadow(color: .black.opacity(0.05), radius: 0.5, y: 1)
    }

    private var moreActions: some View {
        Menu {
            Button("Show Recording in Finder", action: viewModel.showInFinder)
            Button("Open Recording Folder", action: viewModel.openFolder)
            Button("Show Transcript in Finder", action: viewModel.showTranscriptInFinder)
                .disabled(!viewModel.canShowTranscriptInFinder)
            if let title = viewModel.transcriptionActionTitle {
                Divider()
                Button(title, action: viewModel.startProcessing)
            }
        } label: {
            IconView(.more, size: 16)
                .frame(width: 30)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.toolbarIcon)
        .fixedSize()
        .disabled(viewModel.recording == nil)
        .help("More actions")
        .accessibilityLabel("More actions")
    }

    /// `Today, 10:30 · 1:12:40 · 3.1 GB · Screen`, with the media's own duration once it is known.
    private var metadata: String {
        guard let item = viewModel.recording?.item else {
            return ""
        }
        return [
            LibraryFormat.recordedDate(item.recordedAt),
            LibraryFormat.duration(viewModel.duration),
            LibraryFormat.size(item.sizeBytes),
            item.kindLabel
        ]
        .joined(separator: " · ")
    }
}

/// Navigation and transcript operations the Viewer hands to the app. Pausing all processing, the logs and choosing a
/// language here exist only in design scenarios, so those actions default to doing nothing.
struct ViewerWindowActions {
    var backToLibrary: () -> Void = {}
    var openSettings: () -> Void = {}
    var copyTranscript: () -> Void = {}
    var exportTranscript: (ViewerExportFormat) -> Void = { _ in }
    var pauseProcessing: () -> Void = {}
    var showLog: () -> Void = {}
    var chooseLanguage: () -> Void = {}
}

enum ViewerExportFormat: String, CaseIterable, Sendable {
    case txt = "TXT"
    case srt = "SRT"
    case json = "JSON"

    var format: TranscriptFormat {
        switch self {
        case .txt: .text
        case .srt: .subtitles
        case .json: .json
        }
    }

    var contentType: UTType {
        switch self {
        case .txt: .plainText
        case .srt: UTType(filenameExtension: "srt") ?? .plainText
        case .json: .json
        }
    }
}

/// Fixed metrics of the Viewer window.
enum ViewerLayout {
    static let windowWidth: CGFloat = 1100
    static let windowHeight: CGFloat = 750
    static let defaultTranscriptWidth: CGFloat = 380
    /// The transcript panel can be dragged between 320 and 560 pt.
    static let transcriptWidthRange: ClosedRange<CGFloat> = 320...560
    static let minimumPlayerWidth: CGFloat = 420
    /// The simulated clock advances four times a second, as in the design prototype.
    static let clockTick: TimeInterval = 0.25
}

/// The editable title: plain text that shows a fill on hover and a field with an accent ring while editing.
private struct RecordingTitleField: View {
    @Binding var title: String
    let commit: () -> Void

    @FocusState private var isEditing: Bool
    @State private var isHovered = false

    var body: some View {
        TextField("Recording title", text: $title)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .bold))
            .padding(.vertical, 1)
            .padding(.horizontal, 4)
            .frame(width: 280)
            .background(background, in: RoundedRectangle(cornerRadius: 4))
            .focusRing(cornerRadius: 4, isVisible: isEditing)
            .padding(.leading, -4)
            .focused($isEditing)
            .onHover { isHovered = $0 }
            .onSubmit { isEditing = false }
            .onChange(of: isEditing) { _, isNowEditing in
                if !isNowEditing {
                    commit()
                }
            }
            .accessibilityLabel("Recording title")
    }

    private var background: Color {
        if isEditing {
            return VerbatimColor.contentBackground
        }
        return isHovered ? VerbatimColor.fill : .clear
    }
}

/// One half of a joined two-part control: a fill on hover, rounded on its outer edge only.
struct SegmentPartButtonStyle: ButtonStyle {
    let edges: HorizontalEdge

    func makeBody(configuration: Configuration) -> some View {
        SegmentPartBody(configuration: configuration, edges: edges)
    }
}

private struct SegmentPartBody: View {
    let configuration: ButtonStyleConfiguration
    let edges: HorizontalEdge

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background(isHovered || configuration.isPressed ? VerbatimColor.fill : .clear, in: shape)
            .contentShape(shape)
            .focusRing(cornerRadius: 7)
            .onHover { isHovered = $0 }
    }

    private var shape: UnevenRoundedRectangle {
        edges == .leading
            ? UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 7)
            : UnevenRoundedRectangle(bottomTrailingRadius: 7, topTrailingRadius: 7)
    }
}

/// The draggable divider between the player and the transcript. VoiceOver can adjust it too.
private struct TranscriptResizeHandle: View {
    @Binding var width: CGFloat

    @State private var widthAtDragStart: CGFloat?

    var body: some View {
        VerbatimColor.separator
            .frame(width: 0.5)
            .frame(width: 5)
            .padding(.horizontal, -2)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = widthAtDragStart ?? width
                        widthAtDragStart = start
                        width = clamped(start - value.translation.width)
                    }
                    .onEnded { _ in widthAtDragStart = nil }
            )
            .zIndex(1)
            .accessibilityElement()
            .accessibilityLabel("Resize transcript")
            .accessibilityValue(Text("\(Int(width)) points"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: width = clamped(width + 20)
                case .decrement: width = clamped(width - 20)
                @unknown default: break
                }
            }
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, ViewerLayout.transcriptWidthRange.lowerBound), ViewerLayout.transcriptWidthRange.upperBound)
    }
}

#Preview("Video") {
    ViewerWindowView(viewModel: ViewerViewModel(scenario: .video))
        .frame(width: ViewerLayout.windowWidth, height: ViewerLayout.windowHeight)
}

#Preview("Search · dark") {
    ViewerWindowView(viewModel: ViewerViewModel(scenario: .search))
        .frame(width: ViewerLayout.windowWidth, height: ViewerLayout.windowHeight)
        .preferredColorScheme(.dark)
}

#Preview("Audio · teal") {
    ViewerWindowView(viewModel: ViewerViewModel(scenario: .audio), accent: .teal)
        .frame(width: ViewerLayout.windowWidth, height: ViewerLayout.windowHeight)
}

#Preview("Failed") {
    ViewerWindowView(viewModel: ViewerViewModel(scenario: .failed))
        .frame(width: ViewerLayout.windowWidth, height: ViewerLayout.windowHeight)
}
