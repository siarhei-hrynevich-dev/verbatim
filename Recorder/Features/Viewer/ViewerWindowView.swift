import SwiftUI

/// The Viewer window: the player with a floating control HUD on the left, a resizable transcript panel on the
/// right, and the recording's title and file actions in the toolbar.
struct ViewerWindowView: View {
    static let windowID = "viewer"

    @Bindable var viewModel: ViewerViewModel
    /// Overrides the system accent color; `nil` follows the system.
    var accent: VerbatimAccent?
    var actions = ViewerWindowActions()

    @State private var transcriptWidth = ViewerLayout.defaultTranscriptWidth

    var body: some View {
        HStack(spacing: 0) {
            ViewerPlayerView(viewModel: viewModel, openFolder: actions.openFolder)
                .frame(minWidth: ViewerLayout.minimumPlayerWidth)
            TranscriptResizeHandle(width: $transcriptWidth)
            ViewerTranscriptPanel(viewModel: viewModel, actions: actions)
                .frame(width: transcriptWidth)
        }
        .foregroundStyle(VerbatimColor.primaryText)
        .background(VerbatimColor.windowBackground)
        .focusEffectDisabled()
        .navigationTitle(viewModel.title)
        .toolbar { toolbarContent }
        .task(id: viewModel.isPlaying) { await runPlaybackClock() }
        .verbatimAccent(accent)
    }

    /// Advances simulated playback while playing; the task is cancelled when playback stops or the window closes.
    private func runPlaybackClock() async {
        while viewModel.isPlaying, !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(ViewerLayout.clockTick))
            } catch {
                return
            }
            viewModel.advance(by: ViewerLayout.clockTick)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 6) {
                Button(action: actions.backToLibrary) {
                    IconView(.chevronLeft, size: 16)
                        .frame(width: 30)
                }
                .buttonStyle(.toolbarIcon)
                .help("Back to Recordings")
                .accessibilityLabel("Back to Recordings")
                .keyboardShortcut("[", modifiers: .command)

                VStack(alignment: .leading, spacing: 0) {
                    RecordingTitleField(title: $viewModel.title)
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
            Button {
            } label: {
                IconView(.more, size: 16)
                    .frame(width: 30)
            }
            .buttonStyle(.toolbarIcon)
            .help("More actions")
            .accessibilityLabel("More actions")
        }
    }

    /// Show in Finder and the Export menu, joined in one bordered control.
    private var fileActions: some View {
        HStack(spacing: 0) {
            Button(action: actions.showInFinder) {
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

            ViewerExportMenu(hasTranscript: viewModel.recording.hasTranscript, actions: actions)
        }
        .font(.system(size: 12))
        .foregroundStyle(VerbatimColor.primaryText)
        .background(VerbatimColor.controlBackground, in: RoundedRectangle(cornerRadius: 7))
        .hairlineBorder(cornerRadius: 7)
        .shadow(color: .black.opacity(0.05), radius: 0.5, y: 1)
    }

    /// `Today, 10:30 · 1:12:40 · 3.1 GB · Screen`.
    private var metadata: String {
        let item = viewModel.recording.item
        let kind = item.kind == .audio ? String(localized: "Audio") : String(localized: "Screen")
        return [
            LibraryFormat.recordedDate(item.recordedAt),
            LibraryFormat.duration(item.duration),
            LibraryFormat.size(item.sizeBytes),
            kind
        ]
        .joined(separator: " · ")
    }
}

/// Navigation and file operations the Viewer hands to the app. Finder integration, export, processing control
/// and the logs are not implemented yet, so every action defaults to doing nothing.
struct ViewerWindowActions {
    var backToLibrary: () -> Void = {}
    var showInFinder: () -> Void = {}
    var openFolder: () -> Void = {}
    var copyTranscript: () -> Void = {}
    var exportTranscript: (ViewerExportFormat) -> Void = { _ in }
    var showTranscriptInFinder: () -> Void = {}
    var pauseProcessing: () -> Void = {}
    var showLog: () -> Void = {}
    var chooseLanguage: () -> Void = {}
}

enum ViewerExportFormat: String, CaseIterable, Sendable {
    case txt = "TXT"
    case srt = "SRT"
    case json = "JSON"
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
