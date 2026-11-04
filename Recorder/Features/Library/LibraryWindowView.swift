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
    @Environment(\.controlActiveState) private var controlActiveState
    @FocusState private var isListFocused: Bool
    @State private var contextMenuHeight: CGFloat = 0

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(
                viewModel: viewModel,
                openRecordingsFolder: viewModel.openRecordingsFolder,
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
        .sheet(item: renameBinding) { item in
            RenameRecordingSheet(
                currentTitle: item.title,
                rename: { viewModel.rename(item.id, to: $0) },
                cancel: viewModel.cancelRename
            )
        }
        .fileImporter(
            isPresented: locateBinding,
            allowedContentTypes: [.movie, .audio]
        ) { result in
            viewModel.finishLocating(result)
        }
        .alert(
            viewModel.issue?.title ?? "",
            isPresented: issueBinding,
            presenting: viewModel.issue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { issue in
            Text(issue.message)
        }
        // Reloads when the library or the query changes, and whenever the window opens. A closed window does no work.
        .task(id: viewModel.reloadKey) {
            await viewModel.reload()
        }
        // Files may have been moved in Finder while the user was away.
        .onChange(of: controlActiveState) { _, state in
            if state == .key {
                viewModel.windowBecameActive()
            }
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
                    showInFinder: { viewModel.showInFinder(item.id) },
                    openFolder: { viewModel.openFolder(of: item.id) },
                    locate: { viewModel.requestLocate(item.id) },
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
        .toolbar { LibraryToolbar(viewModel: viewModel, newRecording: actions.newRecording) }
        .searchable(
            text: searchBinding,
            placement: .toolbar,
            prompt: Text(viewModel.isPreviewing ? "Search titles and transcripts" : "Search titles and dates")
        )
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.content {
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .failed(let issue):
            LibraryLoadFailedState(issue: issue, retry: viewModel.windowBecameActive)
        case .noResults:
            LibraryNoResultsState(query: viewModel.searchText)
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
                addExistingFiles: viewModel.isPreviewing ? actions.addExistingFiles : nil
            )
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
        case .showInFinder: viewModel.showInFinder(item.id)
        case .openRecordingFolder: viewModel.openFolder(of: item.id)
        case .locateFile: viewModel.requestLocate(item.id)
        case .rename: viewModel.requestRename(item.id)
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

    /// Runs the fix a row offers next to its status: Transcribe, Retry or Locate….
    private func performStatusAction(for item: LibraryItem) {
        if item.isMissing {
            viewModel.requestLocate(item.id)
        } else {
            viewModel.startProcessing(item.id)
        }
    }
}

extension LibraryWindowView {
    fileprivate var searchBinding: Binding<String> {
        Binding(get: { viewModel.searchText }, set: { viewModel.updateSearchText($0) })
    }

    fileprivate var deletionBinding: Binding<LibraryItem?> {
        Binding(
            get: { viewModel.pendingDeletion },
            set: { item in
                if item == nil {
                    viewModel.cancelDeletion()
                }
            }
        )
    }

    fileprivate var renameBinding: Binding<LibraryItem?> {
        Binding(
            get: { viewModel.pendingRename },
            set: { item in
                if item == nil {
                    viewModel.cancelRename()
                }
            }
        )
    }

    fileprivate var locateBinding: Binding<Bool> {
        Binding(
            get: { viewModel.locatingItemID != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.cancelLocate()
                }
            }
        )
    }

    fileprivate var issueBinding: Binding<Bool> {
        Binding(
            get: { viewModel.issue != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissIssue()
                }
            }
        )
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
