import Foundation

/// What is selected and which sheets are open: state of the window, with no effect on the library.
extension LibraryViewModel {
    /// Shows a sidebar section. Like choosing a section in Finder, this ends a search.
    func select(filter: LibraryFilter) {
        self.filter = filter
        searchText = ""
        contextMenuItemID = nil
        if isPreviewing, let selectedItemID, !visibleItems.contains(where: { $0.id == selectedItemID }) {
            self.selectedItemID = nil
        }
    }

    func updateSearchText(_ text: String) {
        searchText = text
        contextMenuItemID = nil
    }

    func select(sortOrder: RecordingSortOrder) {
        self.sortOrder = sortOrder
    }

    func select(_ id: LibraryItem.ID?) {
        selectedItemID = id
        contextMenuItemID = nil
    }

    /// Moves the selection through the visible list, as the arrow keys do. Without a selection, moving down
    /// selects the first recording and moving up the last.
    func moveSelection(by offset: Int) {
        let visible = visibleItems
        guard !visible.isEmpty else {
            return
        }
        guard let selectedItemID, let index = visible.firstIndex(where: { $0.id == selectedItemID }) else {
            select(offset >= 0 ? visible.first?.id : visible.last?.id)
            return
        }
        let newIndex = min(max(index + offset, 0), visible.count - 1)
        select(visible[newIndex].id)
    }

    func showContextMenu(for id: LibraryItem.ID) {
        selectedItemID = id
        contextMenuItemID = id
    }

    func dismissContextMenu() {
        contextMenuItemID = nil
    }

    /// Deleting needs the media; a missing recording can only be located or removed.
    func requestDeletion(of id: LibraryItem.ID) {
        contextMenuItemID = nil
        guard item(withID: id)?.isMissing != true else {
            return
        }
        pendingDeletionID = id
    }

    func cancelDeletion() {
        pendingDeletionID = nil
    }

    func requestRename(_ id: LibraryItem.ID) {
        contextMenuItemID = nil
        renamingItemID = id
    }

    func cancelRename() {
        renamingItemID = nil
    }

    func requestLocate(_ id: LibraryItem.ID) {
        contextMenuItemID = nil
        guard !isPreviewing else {
            return
        }
        locatingItemID = id
    }

    func cancelLocate() {
        locatingItemID = nil
    }

    func dismissIssue() {
        issue = nil
    }
}
