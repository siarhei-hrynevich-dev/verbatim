import Foundation

/// What the user can do to recordings. Each action runs through `perform`, which reports its failure; the service's
/// advancing revision then reloads the list. In a design scenario removals are simulated and the rest do nothing.
extension LibraryViewModel {
    func rename(_ id: LibraryItem.ID, to title: String) {
        renamingItemID = nil
        guard !isPreviewing else {
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index].title = title
            }
            return
        }
        perform { try await $0.rename(id, to: title) }
    }

    /// Removes the recording from the Library and offers Undo. Its files stay in Finder.
    func removeFromLibrary(_ id: LibraryItem.ID) {
        guard !isPreviewing else {
            removeSample(id, offeringUndo: true)
            return
        }
        let index = items.firstIndex { $0.id == id } ?? 0
        guard let item = item(withID: id) else {
            return
        }
        selectNeighbor(of: id)
        perform { [weak self] service in
            let recording = try await service.removeFromLibrary(id)
            self?.lastRemoval = Removal(item: item, index: index, recording: recording)
        }
    }

    /// Moves the recording's files to the Trash, then forgets it.
    func moveToTrash(_ id: LibraryItem.ID) {
        guard !isPreviewing else {
            removeSample(id, offeringUndo: false)
            return
        }
        pendingDeletionID = nil
        lastRemoval = nil
        let nextSelection = neighbor(ofVisibleItem: id)
        perform { [weak self] service in
            let filesLeftBehind = try await service.delete(id)
            if self?.selectedItemID == id {
                self?.selectedItemID = nextSelection
            }
            if !filesLeftBehind.isEmpty {
                self?.issue = .filesLeftBehind(filesLeftBehind)
            }
        }
    }

    func undoRemoval() {
        guard !isPreviewing else {
            undoSampleRemoval()
            return
        }
        perform { [weak self] service in
            guard let removal = self?.lastRemoval, let recording = removal.recording else {
                return
            }
            try await service.restore(recording)
            self?.lastRemoval = nil
            self?.selectedItemID = recording.id
        }
    }

    /// Queues a transcript for the recording: the first one, a retry, or a replacement of what it has. A design
    /// scenario simulates it instead.
    func startProcessing(_ id: LibraryItem.ID) {
        contextMenuItemID = nil
        guard !isPreviewing else {
            startSampleProcessing(id)
            return
        }
        processing?.enqueue(id)
    }

    func cancelProcessing(_ id: LibraryItem.ID) {
        contextMenuItemID = nil
        processing?.cancel(id)
    }

    /// Takes the open panel's answer for the recording being located.
    func finishLocating(_ result: Result<URL, any Error>) {
        guard let id = locatingItemID else {
            return
        }
        locatingItemID = nil
        switch result {
        case .success(let url):
            perform { try await $0.relocate(id, to: url) }
        case .failure(let error):
            issue = LibraryIssue(error)
        }
    }

    func showInFinder(_ id: LibraryItem.ID) {
        perform { try await $0.reveal(id) }
    }

    func openFolder(of id: LibraryItem.ID) {
        perform { try await $0.openFolder(of: id) }
    }

    func openRecordingsFolder() {
        perform { try await $0.openRecordingsFolder() }
    }
}
