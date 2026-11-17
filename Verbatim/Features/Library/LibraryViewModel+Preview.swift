import Foundation

/// Design scenarios: sample recordings and simulated actions that touch nothing on disk.
extension LibraryViewModel {
    /// Simulates starting transcription for a sample recording without a transcript or with failed processing.
    func startSampleProcessing(_ id: LibraryItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].canStartProcessing else {
            return
        }
        items[index].status = .transcribing(progress: Self.initialSampleProgress)
    }

    func apply(_ scenario: LibraryPreviewScenario) {
        isPreviewing = true
        storage = previewData.storage
        items = scenario == .empty ? [] : previewData.items
        filter = scenario == .processing ? .processing : .all
        sortOrder = .newestFirst
        searchText = scenario == .search ? LibraryPreviewScenario.sampleSearchQuery : ""
        lastRemoval = nil
        selectedItemID = sampleItemID(at: Self.selectedSampleIndex(for: scenario))
        contextMenuItemID = scenario == .context ? selectedItemID : nil
        pendingDeletionID = scenario == .confirm ? selectedItemID : nil
    }

    /// Returns to the real library after a design scenario.
    func endPreview() {
        guard service != nil else {
            return
        }
        isPreviewing = false
        items = []
        filter = .all
        sortOrder = .newestFirst
        searchText = ""
        lastRemoval = nil
        selectedItemID = nil
        contextMenuItemID = nil
        pendingDeletionID = nil
        loadState = .loading
    }

    func removeSample(_ id: LibraryItem.ID, offeringUndo: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        selectNeighbor(of: id)
        let removed = items.remove(at: index)
        lastRemoval = offeringUndo ? Removal(item: removed, index: index) : nil
    }

    func undoSampleRemoval() {
        guard let lastRemoval else {
            return
        }
        items.insert(lastRemoval.item, at: min(lastRemoval.index, items.count))
        selectedItemID = lastRemoval.item.id
        self.lastRemoval = nil
    }

    func sampleItemID(at index: Int?) -> LibraryItem.ID? {
        guard let index, items.indices.contains(index) else {
            return nil
        }
        return items[index].id
    }

    /// The design selects Architecture Review, Weekly Team Sync while processing, and Design Critique in the
    /// delete confirmation.
    private static func selectedSampleIndex(for scenario: LibraryPreviewScenario) -> Int? {
        switch scenario {
        case .list, .search, .context: 0
        case .processing: 1
        case .confirm: 5
        case .empty: nil
        }
    }

    /// Restarted processing shows a sliver of progress right away, as in the design prototype.
    private static let initialSampleProgress = 0.02
}
