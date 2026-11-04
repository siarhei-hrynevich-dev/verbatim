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
            let fetched = try await service.recordings(matching: currentQuery(now: currentNow))
            let newCounts = try await loadCounts(from: service, now: currentNow)
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
            counts = newCounts
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

    private func loadCounts(from service: LibraryService, now: Date) async throws -> [LibraryFilter: Int] {
        var counts: [LibraryFilter: Int] = [:]
        for filter in LibraryFilter.allCases {
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
        items = fetched.map {
            LibraryItem($0, inspection: inspections[$0.id], recordingsFolder: recordingsFolder)
        }
        if let selectedItemID, recordings[selectedItemID] == nil {
            self.selectedItemID = nil
        }
    }
}
