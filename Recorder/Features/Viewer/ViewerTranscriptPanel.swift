import SwiftUI

/// The transcript sidebar: a header with search, the timestamped lines, and the follow-playback footer.
///
/// The current line is tinted and marked “Now”, and the list scrolls with playback. Scrolling by hand pauses
/// auto-scroll until Follow Playback is pressed. In the search field, Return or Down steps to the next match and
/// Up to the previous one (also ⌘G and ⇧⌘G); each step moves the playhead to that line.
struct ViewerTranscriptPanel: View {
    let viewModel: ViewerViewModel
    let actions: ViewerWindowActions

    var body: some View {
        VStack(spacing: 0) {
            header
            if viewModel.recording.hasTranscript {
                lineList
                footer
            } else {
                ViewerTranscriptEmptyState(viewModel: viewModel, actions: actions)
            }
        }
        .background(VerbatimColor.transcriptBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transcript")
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Transcript")
                    .font(.system(size: 13, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                if viewModel.recording.hasTranscript {
                    Text("\(viewModel.lines.count) lines · \(viewModel.recording.language)")
                        .font(.system(size: 11))
                        .foregroundStyle(VerbatimColor.secondaryText)
                }
                Spacer(minLength: 0)
                Button(action: actions.copyTranscript) {
                    IconView(.copy, size: 14)
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(PanelIconButtonStyle())
                .disabled(!viewModel.recording.hasTranscript)
                .help("Copy Entire Transcript")
                .accessibilityLabel("Copy Entire Transcript")
            }
            if viewModel.recording.hasTranscript {
                TranscriptSearchBar(viewModel: viewModel)
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var lineList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.lines.enumerated()), id: \.element.id) { index, line in
                        TranscriptLineRow(
                            line: line,
                            isActive: index == viewModel.activeLineIndex,
                            isPlaying: viewModel.isPlaying,
                            query: viewModel.trimmedQuery,
                            isCurrentMatch: index == viewModel.currentMatchLineIndex
                        ) {
                            viewModel.seekToLine(at: index)
                        }
                        .id(line.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .onScrollPhaseChange { _, phase in
                // Programmatic scrolling animates; any other movement comes from the user.
                if phase == .interacting || phase == .decelerating {
                    viewModel.pauseFollowingPlayback()
                }
            }
            .onAppear { scrollToActiveLine(proxy, animated: false) }
            .onChange(of: viewModel.activeLineIndex) { scrollToActiveLine(proxy, animated: true) }
            .onChange(of: viewModel.isFollowingPlayback) { scrollToActiveLine(proxy, animated: true) }
        }
    }

    private func scrollToActiveLine(_ proxy: ScrollViewProxy, animated: Bool) {
        guard viewModel.isFollowingPlayback, let index = viewModel.activeLineIndex else {
            return
        }
        let id = viewModel.lines[index].id
        withAnimation(animated ? .easeInOut(duration: 0.3) : nil) {
            proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.3))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if viewModel.isFollowingPlayback {
                Text("Following playback")
                    .foregroundStyle(VerbatimColor.secondaryText)
            } else {
                Button(action: viewModel.resumeFollowingPlayback) {
                    HStack(spacing: 5) {
                        IconView(.chevronDown, size: 11)
                        Text("Follow Playback")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(VerbatimColor.accent, in: Capsule())
                }
                .buttonStyle(PanelIconButtonStyle(cornerRadius: 11))
                Text("Auto-scroll paused")
                    .foregroundStyle(VerbatimColor.secondaryText)
            }
            Spacer(minLength: 0)
            Text("Click a line to jump")
                .foregroundStyle(VerbatimColor.tertiaryText)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .frame(height: 40)
        .overlay(alignment: .top) {
            VerbatimColor.separator.frame(height: 0.5)
        }
    }
}

/// The search field with its match count, and previous and next buttons.
private struct TranscriptSearchBar: View {
    let viewModel: ViewerViewModel

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                IconView(.search, size: 13)
                    .foregroundStyle(VerbatimColor.secondaryText)
                TextField("Search", text: queryBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit(viewModel.showNextMatch)
                    .onKeyPress(.downArrow) { handle(viewModel.showNextMatch) }
                    .onKeyPress(.upArrow) { handle(viewModel.showPreviousMatch) }
                    .accessibilityLabel("Search transcript")
                Text(matchLabel)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(VerbatimColor.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(VerbatimColor.fill, in: RoundedRectangle(cornerRadius: 7))

            matchButtons
        }
    }

    private var matchButtons: some View {
        let hasMatches = !viewModel.matchingLineIndices.isEmpty
        return HStack(spacing: 0) {
            MatchStepButton(icon: .chevronUp, label: "Previous match", action: viewModel.showPreviousMatch)
                .keyboardShortcut("g", modifiers: [.command, .shift])
            VerbatimColor.separator.frame(width: 0.5, height: 24)
            MatchStepButton(icon: .chevronDown, label: "Next match", action: viewModel.showNextMatch)
                .keyboardShortcut("g", modifiers: .command)
        }
        .background(VerbatimColor.controlBackground, in: RoundedRectangle(cornerRadius: 6))
        .hairlineBorder(cornerRadius: 6)
        .shadow(color: .black.opacity(0.05), radius: 0.5, y: 1)
        .disabled(!hasMatches)
        .opacity(hasMatches ? 1 : 0.4)
    }

    /// `2 of 3`, `No matches`, or nothing without a query.
    private var matchLabel: String {
        guard !viewModel.trimmedQuery.isEmpty else {
            return ""
        }
        let matches = viewModel.matchingLineIndices
        guard !matches.isEmpty else {
            return String(localized: "No matches")
        }
        return String(localized: "\(min(viewModel.currentMatch, matches.count - 1) + 1) of \(matches.count)")
    }

    private var queryBinding: Binding<String> {
        Binding(get: { viewModel.searchText }, set: { viewModel.updateSearchText($0) })
    }

    private func handle(_ action: () -> Void) -> KeyPress.Result {
        action()
        return .handled
    }
}

/// Steps to the previous or next match.
private struct MatchStepButton: View {
    let icon: VerbatimIcon
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconView(icon, size: 12)
                .frame(width: 26, height: 24)
        }
        .buttonStyle(PanelIconButtonStyle(foreground: VerbatimColor.primaryText))
        .accessibilityLabel(label)
    }
}

/// One transcript line. The current line is tinted, its timestamp turns accent and it is marked “Now”.
private struct TranscriptLineRow: View {
    let line: TranscriptLine
    let isActive: Bool
    let isPlaying: Bool
    let query: String
    let isCurrentMatch: Bool
    let seek: () -> Void

    @State private var isHovered = false

    var body: some View {
        let timestamp = RecordingClock.timerText(for: line.start)
        Button(action: seek) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(timestamp)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(isActive ? VerbatimColor.accent : VerbatimColor.secondaryText)
                    Text(line.speaker.label)
                        .foregroundStyle(VerbatimColor.secondaryText)
                    if isActive {
                        Spacer(minLength: 0)
                        nowBadge
                    }
                }
                .font(.system(size: 11))
                Text(highlightedText)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(PanelIconButtonStyle(cornerRadius: 8, foreground: VerbatimColor.primaryText, hoverFill: false))
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(timestamp), \(line.speaker.label): \(line.text)")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .accessibilityHint("Plays from this line")
    }

    private var nowBadge: some View {
        HStack(spacing: 4) {
            IconView(isPlaying ? .audio : .pause, size: 10)
            Text("Now")
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(VerbatimColor.accent)
    }

    private var background: Color {
        if isActive {
            return VerbatimColor.accent.opacity(isHovered ? 0.2 : 0.16)
        }
        return isHovered ? VerbatimColor.fill : .clear
    }

    /// Marks the query in the line; the current match is brighter than the others.
    private var highlightedText: AttributedString {
        var text = AttributedString(line.text)
        guard !query.isEmpty else {
            return text
        }
        var searchStart = text.startIndex
        while let range = text[searchStart...].range(of: query, options: .caseInsensitive) {
            text[range].backgroundColor = isCurrentMatch ? Self.currentMatch : Self.otherMatch
            searchStart = range.upperBound
        }
        return text
    }

    private static let currentMatch = Color(red: 1, green: 204 / 255, blue: 0).opacity(0.9)
    private static let otherMatch = Color(red: 1, green: 214 / 255, blue: 10 / 255).opacity(0.4)
}

/// A small panel button: secondary icon, fill on hover, dimmed when disabled, with a visible focus ring.
struct PanelIconButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 5
    var foreground = VerbatimColor.secondaryText
    var hoverFill = true

    func makeBody(configuration: Configuration) -> some View {
        PanelIconButtonBody(style: self, configuration: configuration)
    }
}

private struct PanelIconButtonBody: View {
    let style: PanelIconButtonStyle
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius)
        configuration.label
            .foregroundStyle(style.foreground)
            .background(showsFill ? VerbatimColor.fill : .clear, in: shape)
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .focusRing(cornerRadius: style.cornerRadius)
            .onHover { isHovered = $0 }
    }

    private var showsFill: Bool {
        style.hoverFill && isEnabled && (isHovered || configuration.isPressed)
    }
}
