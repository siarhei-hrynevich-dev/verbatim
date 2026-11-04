import SwiftUI

/// The Library window: a sidebar of sections, then the recordings list, search results or the empty state, with
/// the selected recording's folder in a path bar at the bottom.
struct LibraryWindowView: View {
    static let windowID = "library"

    @Bindable var viewModel: LibraryViewModel
    /// Overrides the system accent color; `nil` follows the system.
    var accent: VerbatimAccent?
    var actions = LibraryWindowActions()

    @Environment(\.undoManager) private var undoManager
    @FocusState private var isListFocused: Bool
    @State private var contextMenuHeight: CGFloat = 0

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(
                viewModel: viewModel,
                openRecordingsFolder: { actions.openRecordingFolder(nil) },
                openSettings: actions.openSettings
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: LibraryLayout.sidebarWidth, max: 320)
            // Split view columns are hosted separately and do not inherit the accent from the split view itself.
            .verbatimAccent(accent)
        } detail: {
            detail
                .verbatimAccent(accent)
        }
        .focusEffectDisabled()
        .navigationTitle("Recordings Library")
        .sheet(item: deletionBinding) { item in
            DeleteRecordingSheet(
                item: item,
                storage: viewModel.storage,
                removeFromLibrary: { removeFromLibrary(item.id) },
                cancel: viewModel.cancelDeletion,
                moveToTrash: { viewModel.moveToTrash(item.id) }
            )
        }
        .verbatimAccent(accent)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if viewModel.showsProcessingNote {
                LibraryProcessingNote(pauseAll: actions.pauseProcessing)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let item = viewModel.pathBarItem {
                LibraryPathBar(
                    item: item,
                    storage: viewModel.storage,
                    showInFinder: { actions.showInFinder(item.id) },
                    openFolder: { actions.openRecordingFolder(item.id) },
                    locate: { actions.locate(item.id) },
                    removeFromLibrary: { removeFromLibrary(item.id) }
                )
            }
        }
        .frame(minWidth: LibraryLayout.minimumDetailWidth)
        .foregroundStyle(VerbatimColor.primaryText)
        .background(VerbatimColor.contentBackground)
        .overlayPreferenceValue(LibraryRowAnchorKey.self) { anchors in
            contextMenuLayer(rowAnchors: anchors)
        }
        .overlay(alignment: .bottom) {
            if let removal = viewModel.lastRemoval {
                LibraryUndoToast(title: removal.item.title, undo: undoRemovalFromToast)
                    .padding(.bottom, LibraryLayout.toastBottomOffset)
            }
        }
        .toolbar { toolbarContent }
        .searchable(text: searchBinding, placement: .toolbar, prompt: Text("Search titles and transcripts"))
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.content {
        case .recordings:
            LibraryRecordingList(
                viewModel: viewModel,
                isFocused: $isListFocused,
                openRecording: { actions.openRecording($0, nil) },
                performStatusAction: performStatusAction
            )
        case .searchResults(let results):
            LibrarySearchResultsView(
                results: results,
                query: viewModel.searchText,
                openRecording: actions.openRecording
            )
        case .empty:
            LibraryEmptyState(
                folderPath: viewModel.storage.folderPath,
                startRecording: actions.newRecording,
                addExistingFiles: actions.addExistingFiles
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(VerbatimColor.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(VerbatimColor.secondaryText)
            }
            .lineLimit(1)
            .padding(.leading, 8)
            .fixedSize()
            .accessibilityElement(children: .combine)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: viewModel.toggleSortOrder) {
                HStack(spacing: 6) {
                    IconView(.sort, size: 14)
                    Text(sortTitle)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 8)
            }
            .buttonStyle(.toolbarIcon)
            .help("Sort")
            .accessibilityLabel("Sort")
            .accessibilityValue(sortTitle)

            Button(action: actions.newRecording) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(VerbatimColor.red)
                        .frame(width: 10, height: 10)
                    Text("New Recording")
                }
                .font(.system(size: 12))
                .foregroundStyle(VerbatimColor.primaryText)
                .padding(.horizontal, 10)
            }
            .buttonStyle(.toolbarIcon)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help("New Recording (⌘⇧R)")
        }
    }

    private var title: String {
        viewModel.isSearching ? String(localized: "Search") : viewModel.filter.title
    }

    private var subtitle: String {
        if viewModel.items.isEmpty {
            return String(localized: "No recordings")
        }
        if case .searchResults(let results) = viewModel.content {
            return LibraryFormat.count(results.resultCount, singular: "result", plural: "results")
        }
        let recordings = LibraryFormat.count(viewModel.visibleItems.count, singular: "recording", plural: "recordings")
        if viewModel.filter == .processing {
            let counts = viewModel.processingCounts
            return "\(recordings) · \(counts.transcribing) transcribing, \(counts.indexing) indexing"
        }
        return "\(recordings) · \(LibraryFormat.size(viewModel.storage.usedBytes)) on disk"
    }

    private var sortTitle: String {
        switch viewModel.sortOrder {
        case .newestFirst: String(localized: "Newest First")
        case .oldestFirst: String(localized: "Oldest First")
        }
    }

    // MARK: - Context menu

    /// The menu opens below the row's top edge, at the design's fixed inset from the list's leading edge, and
    /// flips above the row when it would run past the bottom of the window.
    @ViewBuilder
    private func contextMenuLayer(rowAnchors: [LibraryItem.ID: Anchor<CGRect>]) -> some View {
        if let item = viewModel.contextMenuItem {
            GeometryReader { proxy in
                let rowFrame = rowAnchors[item.id].map { proxy[$0] }
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.dismissContextMenu() }
                        .accessibilityHidden(true)
                    LibraryContextMenu(
                        item: item,
                        perform: { perform($0, on: item) },
                        dismiss: dismissContextMenuFromKeyboard
                    )
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: {
                        contextMenuHeight = $0
                    }
                    .offset(
                        x: LibraryLayout.contextMenuLeading,
                        y: contextMenuTop(rowFrame: rowFrame, containerHeight: proxy.size.height)
                    )
                }
            }
        }
    }

    private func contextMenuTop(rowFrame: CGRect?, containerHeight: CGFloat) -> CGFloat {
        guard let rowFrame else {
            return LibraryLayout.contextMenuRowOffset
        }
        let below = rowFrame.minY + LibraryLayout.contextMenuRowOffset
        guard below + contextMenuHeight > containerHeight - LibraryLayout.contextMenuMargin else {
            return below
        }
        let above = rowFrame.minY + LibraryLayout.contextMenuFlippedRowOffset - contextMenuHeight
        return max(LibraryLayout.contextMenuMargin, above)
    }

    private func dismissContextMenuFromKeyboard() {
        viewModel.dismissContextMenu()
        isListFocused = true
    }

    private func perform(_ command: LibraryContextMenu.Command, on item: LibraryItem) {
        dismissContextMenuFromKeyboard()
        switch command {
        case .openRecording: actions.openRecording(item.id, nil)
        case .openTranscript: actions.openTranscript(item.id)
        case .showInFinder: actions.showInFinder(item.id)
        case .openRecordingFolder: actions.openRecordingFolder(item.id)
        case .rename: actions.rename(item.id)
        case .retryProcessing: viewModel.startProcessing(item.id)
        case .removeFromLibrary: removeFromLibrary(item.id)
        case .deleteRecording: viewModel.requestDeletion(of: item.id)
        }
    }

    // MARK: - Removal and undo

    /// Removes a recording and registers the removal with the window's undo manager, so Edit › Undo and ⌘Z
    /// restore it like the toast's Undo button.
    private func removeFromLibrary(_ id: LibraryItem.ID) {
        viewModel.removeFromLibrary(id)
        guard let undoManager else {
            return
        }
        undoManager.registerUndo(withTarget: viewModel) { viewModel in
            viewModel.undoRemoval()
        }
        undoManager.setActionName(String(localized: "Remove from Library"))
    }

    private func undoRemovalFromToast() {
        viewModel.undoRemoval()
        undoManager?.removeAllActions(withTarget: viewModel)
    }

    // MARK: - Helpers

    /// Runs the fix a row offers next to its status: Transcribe, Retry or Locate….
    private func performStatusAction(for item: LibraryItem) {
        if item.status == .missing {
            actions.locate(item.id)
        } else {
            viewModel.startProcessing(item.id)
        }
    }

    private var searchBinding: Binding<String> {
        Binding(get: { viewModel.searchText }, set: { viewModel.updateSearchText($0) })
    }

    private var deletionBinding: Binding<LibraryItem?> {
        Binding(
            get: { viewModel.pendingDeletion },
            set: { item in
                if item == nil {
                    viewModel.cancelDeletion()
                }
            }
        )
    }
}

/// Navigation to other windows and file operations, which the Library hands to the app. The Viewer, Finder
/// integration and processing control are not implemented yet, so every action defaults to doing nothing.
struct LibraryWindowActions {
    /// Opens a recording in the Viewer, optionally at a transcript position in seconds.
    var openRecording: (LibraryItem.ID, TimeInterval?) -> Void = { _, _ in }
    var openTranscript: (LibraryItem.ID) -> Void = { _ in }
    var newRecording: () -> Void = {}
    var openSettings: () -> Void = {}
    var showInFinder: (LibraryItem.ID) -> Void = { _ in }
    /// Opens a recording's folder, or the recordings folder itself for `nil`.
    var openRecordingFolder: (LibraryItem.ID?) -> Void = { _ in }
    var locate: (LibraryItem.ID) -> Void = { _ in }
    var rename: (LibraryItem.ID) -> Void = { _ in }
    var addExistingFiles: () -> Void = {}
    var pauseProcessing: () -> Void = {}
}

/// Fixed metrics of the Library window.
enum LibraryLayout {
    static let windowWidth: CGFloat = 1000
    static let windowHeight: CGFloat = 700
    static let sidebarWidth: CGFloat = 220
    static let minimumDetailWidth: CGFloat = 640
    /// The undo toast floats 46 pt above the bottom of the window.
    static let toastBottomOffset: CGFloat = 46
    static let contextMenuLeading: CGFloat = 236
    static let contextMenuRowOffset: CGFloat = 30
    static let contextMenuFlippedRowOffset: CGFloat = 14
    static let contextMenuMargin: CGFloat = 8
}

extension LibraryFilter {
    var title: String {
        switch self {
        case .all: String(localized: "All Recordings")
        case .recent: String(localized: "Recent")
        case .processing: String(localized: "Processing")
        case .screen: String(localized: "Screen Recordings")
        case .audio: String(localized: "Audio Recordings")
        }
    }

    var icon: VerbatimIcon {
        switch self {
        case .all: .list
        case .recent: .clock
        case .processing: .loader
        case .screen: .monitor
        case .audio: .audio
        }
    }
}

#Preview("Recordings") {
    LibraryWindowView(viewModel: LibraryViewModel(scenario: .list))
        .frame(width: LibraryLayout.windowWidth, height: LibraryLayout.windowHeight)
}

#Preview("Processing · dark, indigo") {
    LibraryWindowView(viewModel: LibraryViewModel(scenario: .processing), accent: .indigo)
        .frame(width: LibraryLayout.windowWidth, height: LibraryLayout.windowHeight)
        .preferredColorScheme(.dark)
}

#Preview("Search results") {
    LibraryWindowView(viewModel: LibraryViewModel(scenario: .search))
        .frame(width: LibraryLayout.windowWidth, height: LibraryLayout.windowHeight)
}

#Preview("Context menu · teal") {
    LibraryWindowView(viewModel: LibraryViewModel(scenario: .context), accent: .teal)
        .frame(width: LibraryLayout.windowWidth, height: LibraryLayout.windowHeight)
}

#Preview("Delete confirmation") {
    LibraryWindowView(viewModel: LibraryViewModel(scenario: .confirm))
        .frame(width: LibraryLayout.windowWidth, height: LibraryLayout.windowHeight)
}

#Preview("Empty · dark") {
    LibraryWindowView(viewModel: LibraryViewModel(scenario: .empty))
        .frame(width: LibraryLayout.windowWidth, height: LibraryLayout.windowHeight)
        .preferredColorScheme(.dark)
}
