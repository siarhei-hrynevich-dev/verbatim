import SwiftUI

/// The actions menu for one recording, opened by a secondary click or the row's More button.
///
/// Remove from Library and Delete Recording sit apart, each with a line stating what happens to the files. The
/// menu takes keyboard focus when it opens: Up and Down move the highlight over enabled items, Return or Space
/// runs it, and Escape closes the menu.
struct LibraryContextMenu: View {
    enum Command: CaseIterable {
        case openRecording
        case openTranscript
        case showInFinder
        case openRecordingFolder
        case rename
        case retryProcessing
        case removeFromLibrary
        case deleteRecording
    }

    let item: LibraryItem
    let perform: (Command) -> Void
    let dismiss: () -> Void

    @State private var highlightedCommand: Command?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Self.sections.enumerated()), id: \.offset) { index, section in
                if index > 0 {
                    VerbatimColor.separator
                        .frame(height: 0.5)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 9)
                }
                ForEach(section, id: \.self, content: menuItem)
            }
        }
        .padding(5)
        .frame(width: 250)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 9)
                .fill(VerbatimColor.menuBackground)
        }
        .hairlineBorder(cornerRadius: 9, color: VerbatimColor.edge)
        .shadow(color: .black.opacity(0.22), radius: 15, y: 10)
        .focusable(interactions: .edit)
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.downArrow) { moveHighlight(by: 1) }
        .onKeyPress(.upArrow) { moveHighlight(by: -1) }
        .onKeyPress(keys: [.return, .space]) { _ in performHighlightedCommand() }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onExitCommand(perform: dismiss)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions for \(item.title)")
        .accessibilityAddTraits(.isModal)
    }

    private func menuItem(_ command: Command) -> some View {
        let isEnabled = command.isEnabled(for: item)
        let isHighlighted = isEnabled && command == highlightedCommand
        return Button {
            perform(command)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(command.title)
                        .fontWeight(command.isDefault ? .semibold : .regular)
                    if let subtitle = command.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .opacity(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let keyEquivalent = command.keyEquivalent {
                    Text(keyEquivalent)
                        .font(.system(size: 12))
                        .opacity(0.55)
                        .accessibilityHidden(true)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(foreground(for: command, isHighlighted: isHighlighted))
            .padding(.vertical, 3)
            .padding(.horizontal, 9)
            .frame(minHeight: 22)
            .background(isHighlighted ? VerbatimColor.accent : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { isHovering in
            if isHovering, isEnabled {
                highlightedCommand = command
            } else if highlightedCommand == command {
                highlightedCommand = nil
            }
        }
        .accessibilityHint(command.subtitle ?? "")
    }

    private func foreground(for command: Command, isHighlighted: Bool) -> Color {
        if isHighlighted {
            return .white
        }
        return command.isDestructive ? VerbatimColor.red : VerbatimColor.primaryText
    }

    private func moveHighlight(by offset: Int) -> KeyPress.Result {
        let enabled = Self.sections.flatMap { $0 }.filter { $0.isEnabled(for: item) }
        guard !enabled.isEmpty else {
            return .handled
        }
        guard let highlightedCommand, let index = enabled.firstIndex(of: highlightedCommand) else {
            self.highlightedCommand = offset > 0 ? enabled.first : enabled.last
            return .handled
        }
        self.highlightedCommand = enabled[(index + offset + enabled.count) % enabled.count]
        return .handled
    }

    private func performHighlightedCommand() -> KeyPress.Result {
        guard let highlightedCommand else {
            return .ignored
        }
        perform(highlightedCommand)
        return .handled
    }

    private static let sections: [[Command]] = [
        [.openRecording, .openTranscript],
        [.showInFinder, .openRecordingFolder],
        [.rename, .retryProcessing],
        [.removeFromLibrary, .deleteRecording]
    ]
}

extension LibraryContextMenu.Command {
    var title: LocalizedStringKey {
        switch self {
        case .openRecording: "Open Recording"
        case .openTranscript: "Open Transcript"
        case .showInFinder: "Show in Finder"
        case .openRecordingFolder: "Open Recording Folder"
        case .rename: "Rename"
        case .retryProcessing: "Retry Processing"
        case .removeFromLibrary: "Remove from Library"
        case .deleteRecording: "Delete Recording…"
        }
    }

    /// States what happens to the files on disk.
    var subtitle: String? {
        switch self {
        case .removeFromLibrary: String(localized: "Files stay in Finder")
        case .deleteRecording: String(localized: "Moves files to the Trash")
        default: nil
        }
    }

    var keyEquivalent: String? {
        switch self {
        case .openRecording: "↩"
        case .showInFinder: "⌘R"
        case .openRecordingFolder: "⌥⌘R"
        case .deleteRecording: "⌘⌫"
        default: nil
        }
    }

    /// The action a double-click or Return performs, shown in bold.
    var isDefault: Bool {
        self == .openRecording
    }

    var isDestructive: Bool {
        self == .deleteRecording
    }

    func isEnabled(for item: LibraryItem) -> Bool {
        switch self {
        case .openTranscript: item.status == .ready
        case .retryProcessing: item.canStartProcessing
        default: true
        }
    }
}
