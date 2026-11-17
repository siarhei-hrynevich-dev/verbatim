import Foundation

/// Fetching what the window shows. The database filters and sorts; the file system is checked afterwards.
extension LibraryViewModel {
    /// Fetches what the current section, search and order call for. Rows appear right away, then the file system is
    /// checked, so a slow or unmounted volume never holds up the list. A newer reload cancels this one.
    func reload() async {
        guard let service, !isPreviewing else {
            return
        }
        do {
            let currentNow = now
            let fetchedTags = try await service.tags()
            let fetched = try await service.recordings(matching: currentQuery(now: currentNow))
            let newCounts = try await loadCounts(from: service, tags: fetchedTags, now: currentNow)
            let usedBytes = try await service.totalFileSize()
            let location = await service.recordingsFolder()
            guard !Task.isCancelled else {
                return
            }
            storage = LibraryStorage(
                folderPath: location.displayPath,
                usedBytes: usedBytes,
                freeBytes: location.availableBytes
            )
            tags = fetchedTags
            counts = newCounts
            if case .tagged(let id) = filter, !fetchedTags.contains(where: { $0.id == id }) {
                // The tag was deleted, possibly elsewhere, so there is nothing left to show.
                filter = .all
            }
            loadState = .loaded
            show(fetched, inspections: inspections(of: fetched), recordingsFolder: location.url)

            let inspected = await service.inspect(fetched)
            guard !Task.isCancelled else {
                return
            }
            show(fetched, inspections: inspected, recordingsFolder: location.url)
        } catch {
            Self.logger.error("Could not load the Library: \(String(describing: error))")
            guard !Task.isCancelled else {
                return
            }
            items = []
            loadState = .failed(LibraryIssue(error))
        }
    }

    /// Asks for a reload, as files may have changed while the window was in the background.
    func windowBecameActive() {
        refreshCount += 1
    }

    func thumbnail(for id: LibraryItem.ID) async -> Data? {
        guard let service, let recording = recordings[id] else {
            return nil
        }
        return await service.thumbnail(for: recording)
    }

    private func currentQuery(now: Date) -> RecordingQuery {
        var query = RecordingQuery()
        if isSearching {
            // Like the design's search, this looks across the whole library rather than one section.
            let dates = RecordingDateSearch(now: now, calendar: calendar)
            query.search = RecordingQuery.Search(
                text: trimmedSearchText,
                recordedDuring: dates.interval(matching: trimmedSearchText)
            )
        } else {
            query = filter.query(now: now, calendar: calendar)
        }
        query.sortOrder = sortOrder
        return query
    }

    private func loadCounts(
        from service: LibraryService,
        tags: [RecordingTag],
        now: Date
    ) async throws -> [LibraryFilter: Int] {
        var counts: [LibraryFilter: Int] = [:]
        for filter in LibraryFilter.fixedSections + tags.map({ .tagged($0.id) }) {
            counts[filter] = try await service.count(matching: filter.query(now: now, calendar: calendar))
        }
        return counts
    }

    /// Until a recording is checked again, what was last known about it stands.
    private func inspections(of fetched: [LibraryRecording]) -> [UUID: RecordingFileInspection] {
        var known: [UUID: RecordingFileInspection] = [:]
        for recording in fetched {
            known[recording.id] = lastInspections[recording.id]
        }
        return known
    }

    private func show(
        _ fetched: [LibraryRecording],
        inspections: [UUID: RecordingFileInspection],
        recordingsFolder: URL
    ) {
        lastInspections = inspections
        recordings = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        items = fetched.map { recording in
            LibraryItem(
                recording,
                inspection: inspections[recording.id],
                recordingsFolder: recordingsFolder,
                job: processing?.job(for: recording.id),
                isProcessingAvailable: processing != nil,
                tags: tags.filter { recording.tagIDs.contains($0.id) }
            )
        }
        if let selectedItemID, recordings[selectedItemID] == nil {
            self.selectedItemID = nil
        }
    }

    /// Progress changes too often to go through the database, so it joins the stored status here, as do the summary
    /// and search index, which are only ever in memory.
    func withMeasuredProgress(_ item: LibraryItem) -> LibraryItem {
        var measured = item
        switch item.status {
        case .transcribing:
            guard let fraction = processing?.progress[item.id] else {
                return item
            }
            measured.status = .transcribing(progress: fraction)
        case .ready:
            let summary = summaries?.job(for: item.id)
            let index = indexing?.job(for: item.id)
            guard let status = LibraryItem.Status(summary: summary, indexing: index) else {
                return item
            }
            measured.status = status
        default:
            return item
        }
        return measured
    }
}
