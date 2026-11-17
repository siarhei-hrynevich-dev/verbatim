import SwiftUI

/// The recordings table: a column header and one row per recording.
///
/// The list is a single keyboard focus stop, like a native table: Up and Down move the selection, Return opens
/// the selected recording, Delete asks to delete it, and Escape closes the context menu. While the list has focus,
/// the selected row shows the focus ring.
struct LibraryRecordingList: View {
    let viewModel: LibraryViewModel
    let isFocused: FocusState<Bool>.Binding
    let openRecording: (LibraryItem.ID) -> Void
    let performStatusAction: (LibraryItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            columnHeader
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.visibleItems) { item in
                            row(for: item)
                                .id(item.id)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)
                }
                .onChange(of: viewModel.selectedItemID) { _, selectedItemID in
                    guard let selectedItemID else {
                        return
                    }
                    proxy.scrollTo(selectedItemID)
                }
            }
            .background { keyboardTarget }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Recordings")
        }
        // Like a table in Finder or Mail, the list takes keyboard focus when the window opens.
        .onAppear { isFocused.wrappedValue = true }
    }

    /// Holds the list's keyboard focus behind the rows. Keeping it out of the rows' ancestry matters: controls read
    /// the nearest focused ancestor as their own focus, so a focused container would ring every button in it.
    private var keyboardTarget: some View {
        Color.clear
            .focusable(interactions: .edit)
            .focused(isFocused)
            .onKeyPress(.upArrow) { handle { viewModel.moveSelection(by: -1) } }
            .onKeyPress(.downArrow) { handle { viewModel.moveSelection(by: 1) } }
            .onKeyPress(.return) { handle(openSelectedRecording) }
            .onKeyPress(keys: ["r"]) { handleFinderShortcut($0) }
            .onKeyPress { press in
                guard Self.isDeleteKey(press) else {
                    return .ignored
                }
                return handle(requestDeletionOfSelection)
            }
            .onKeyPress(.escape) {
                guard viewModel.contextMenuItemID != nil else {
                    return .ignored
                }
                viewModel.dismissContextMenu()
                return .handled
            }
            .accessibilityHidden(true)
    }

    /// Delete (⌫, also with ⌘) or Forward Delete. The Delete key reports U+007F, which `KeyEquivalent.delete`
    /// (U+0008) does not match.
    private static func isDeleteKey(_ press: KeyPress) -> Bool {
        press.key == .delete || press.key == .deleteForward || press.characters == "\u{7F}"
    }

    private var columnHeader: some View {
        HStack(spacing: LibraryColumn.spacing) {
            Color.clear.libraryColumn(.thumbnail)
            Text("Name").libraryColumn(.name)
            Text("Date").libraryColumn(.date)
            Text("Duration").libraryColumn(.duration)
            Text("Size").libraryColumn(.size)
            Text("Status").libraryColumn(.status)
            Color.clear.libraryColumn(.actions)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(VerbatimColor.secondaryText)
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .frame(height: 28)
        .overlay(alignment: .bottom) {
            VerbatimColor.separator.frame(height: 0.5)
        }
        // Each row reads out its own values, so the header adds nothing for VoiceOver.
        .accessibilityHidden(true)
    }

    private func row(for item: LibraryItem) -> some View {
        let isSelected = item.id == viewModel.selectedItemID
        return LibraryRecordingRow(
            item: item,
            isSelected: isSelected,
            showsFocusRing: isSelected && isFocused.wrappedValue,
            select: {
                viewModel.select(item.id)
                isFocused.wrappedValue = true
            },
            open: { openRecording(item.id) },
            showActions: { viewModel.showContextMenu(for: item.id) },
            requestDeletion: { viewModel.requestDeletion(of: item.id) },
            performStatusAction: { performStatusAction(item) },
            loadThumbnail: { await viewModel.thumbnail(for: item.id) }
        )
        .anchorPreference(key: LibraryRowAnchorKey.self, value: .bounds) { anchor in
            item.id == viewModel.contextMenuItemID ? [item.id: anchor] : [:]
        }
    }

    private func openSelectedRecording() {
        if let selectedItemID = viewModel.selectedItemID {
            openRecording(selectedItemID)
        }
    }

    private func requestDeletionOfSelection() {
        if let selectedItemID = viewModel.selectedItemID {
            viewModel.requestDeletion(of: selectedItemID)
        }
    }

    /// ⌘R shows the selected recording in Finder and ⌥⌘R opens its folder, as the actions menu says.
    private func handleFinderShortcut(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.contains(.command), let item = viewModel.selectedItem, !item.isMissing else {
            return .ignored
        }
        if press.modifiers.contains(.option) {
            viewModel.openFolder(of: item.id)
        } else {
            viewModel.showInFinder(item.id)
        }
        return .handled
    }

    private func handle(_ action: () -> Void) -> KeyPress.Result {
        action()
        return .handled
    }
}

/// Bounds of the row whose context menu is open, so the window can place the menu next to it.
struct LibraryRowAnchorKey: PreferenceKey {
    static var defaultValue: Value {
        [:]
    }

    typealias Value = [LibraryItem.ID: Anchor<CGRect>]

    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue()) { $1 }
    }
}

/// The table's columns at the design's fixed widths, with the name column taking the remaining space.
enum LibraryColumn {
    case thumbnail
    case name
    case date
    case duration
    case size
    case status
    case actions

    static let spacing: CGFloat = 12

    /// `nil` for the flexible name column.
    var width: CGFloat? {
        switch self {
        case .thumbnail: 56
        case .name: nil
        case .date: 112
        case .duration, .size: 64
        case .status: 170
        case .actions: 28
        }
    }

    var alignment: Alignment {
        switch self {
        case .duration, .size: .trailing
        case .actions: .center
        case .thumbnail, .name, .date, .status: .leading
        }
    }
}

extension View {
    /// Sizes a cell to its table column.
    func libraryColumn(_ column: LibraryColumn) -> some View {
        frame(minWidth: column.width ?? 0, maxWidth: column.width ?? .infinity, alignment: column.alignment)
    }
}
