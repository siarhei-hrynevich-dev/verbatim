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

    /// Adds the tag to the recording, or removes it when it already has it. Tags toggle independently.
    func toggleTag(_ tag: RecordingTag, on id: LibraryItem.ID) {
        guard let item = item(withID: id) else {
            return
        }
        var chosen = tags.filter { candidate in item.tags.contains { $0.id == candidate.id } }
        if let index = chosen.firstIndex(of: tag) {
            chosen.remove(at: index)
        } else {
            chosen.append(tag)
        }
        guard !isPreviewing else {
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index].tags = tags.filter(chosen.contains)
            }
            return
        }
        let ids = Set(chosen.map(\.id))
        perform { try await $0.setTags(ids, for: id) }
    }

    // MARK: - Managing tags

    func requestNewTag() {
        tagEditing = .new
    }

    func requestEditing(_ tag: RecordingTag) {
        tagEditing = .existing(tag)
    }

    func cancelTagEditing() {
        tagEditing = nil
    }

    /// Saves the open tag sheet and closes it. A failure, such as a name another tag has, is presented afterwards.
    func saveTag(named name: String, color: TagColor) {
        let editing = tagEditing
        tagEditing = nil
        switch editing {
        case .new:
            perform { try await $0.createTag(named: name, color: color) }
        case .existing(let tag):
            perform { try await $0.editTag(tag.id, name: name, color: color) }
        case nil:
            break
        }
    }

    func requestTagDeletion(_ tag: RecordingTag) {
        pendingTagDeletionID = tag.id
    }

    func cancelTagDeletion() {
        pendingTagDeletionID = nil
    }

    func deleteTag(_ id: RecordingTag.ID) {
        pendingTagDeletionID = nil
        perform { [weak self] service in
            try await service.deleteTag(id)
            if self?.filter == .tagged(id) {
                self?.filter = .all
            }
        }
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
