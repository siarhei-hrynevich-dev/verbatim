import Foundation
import Observation
import os

/// The recording library's use cases and the rules connecting its database entries to the files they describe.
///
/// Created by App and independent of any window. Every operation that changes the library advances `revision`, which
/// is how the Library window knows to reload without polling. Database and file work happens on the injected actors,
/// never on the main actor.
@MainActor
@Observable
final class LibraryService: FinishedRecordingRegistry {
    /// Advances whenever the library's contents change.
    private(set) var revision = 0

    /// Told when a recording leaves, so work on it stops. Added by App; held weakly.
    @ObservationIgnored private var removalObservers: [WeakRemovalObserver] = []
    @ObservationIgnored private let repository: any RecordingRepository
    @ObservationIgnored private let fileStore: any RecordingFileStore
    @ObservationIgnored private let thumbnails: any RecordingThumbnailProvider
    @ObservationIgnored private let destinations: any RecordingDestinationStore

    init(
        repository: any RecordingRepository,
        fileStore: any RecordingFileStore,
        thumbnails: any RecordingThumbnailProvider,
        destinations: any RecordingDestinationStore
    ) {
        self.repository = repository
        self.fileStore = fileStore
        self.thumbnails = thumbnails
        self.destinations = destinations
    }

    func addRemovalObserver(_ observer: any RecordingRemovalObserving) {
        removalObservers.append(WeakRemovalObserver(observer: observer))
    }

    private func notifyRemoval(of id: UUID, permanently: Bool) {
        removalObservers.removeAll { $0.observer == nil }
        for entry in removalObservers {
            entry.observer?.recordingRemoved(id, permanently: permanently)
        }
    }

    // MARK: - Reading

    func recordings(matching query: RecordingQuery) async throws -> [LibraryRecording] {
        try await repository.fetch(matching: query)
    }

    /// Throws `LibraryError.recordingNotFound` when the Library has no such entry.
    func recording(withID id: UUID) async throws -> LibraryRecording {
        try await existingRecording(id)
    }

    /// Opens the media for reading that lasts until the returned file is closed. Reads the entry afresh, so a file that
    /// was just moved or located is found.
    func openMedia(of id: UUID) async throws -> OpenMediaFile {
        try await fileStore.openMedia(of: existingRecording(id))
    }

    func count(matching query: RecordingQuery) async throws -> Int {
        try await repository.count(matching: query)
    }

    func totalFileSize() async throws -> Int64 {
        try await repository.totalFileSize()
    }

    func recordingsFolder() async -> RecordingLocation {
        await destinations.currentLocation()
    }

    /// Checks recordings against the file system. A file that was moved and found again through its bookmark gets
    /// its stored reference updated; failing to store that only means finding it again next time.
    func inspect(_ recordings: [LibraryRecording]) async -> [UUID: RecordingFileInspection] {
        var inspections: [UUID: RecordingFileInspection] = [:]
        for recording in recordings {
            let inspection = await fileStore.inspect(recording)
            inspections[recording.id] = inspection
            guard inspection.media != recording.media else {
                continue
            }
            do {
                // Read afresh: only the location changes, and a job may have moved the status on since then.
                guard var moved = try await repository.fetch(id: recording.id) else {
                    continue
                }
                moved.media = inspection.media
                try await repository.update(moved)
            } catch {
                Self.logger.error("Could not store a moved file's location: \(String(describing: error))")
            }
        }
        return inspections
    }

    func thumbnail(for recording: LibraryRecording) async -> Data? {
        await thumbnails.thumbnail(for: recording)
    }

    // MARK: - Adding

    /// The file is checked once more on its way in: only media that exists gets an entry. Failing here leaves the
    /// media untouched.
    func addFinishedRecording(_ metadata: RecordingMetadata, destination: RecordingDestination) async throws {
        let snapshot = try await fileStore.describeMedia(at: destination.mediaURL)
        let recording = LibraryRecording(
            recording: metadata.recording,
            captureMode: metadata.captureMode,
            media: snapshot.media,
            fileSizeBytes: snapshot.fileSizeBytes
        )
        try await repository.insert(recording)
        revision += 1
    }

    // MARK: - Editing

    /// Changes the title only; the file and folder keep their names, which keeps references to them stable.
    func rename(_ id: UUID, to title: String) async throws {
        let recording = try await existingRecording(id)
        let renamed: Recording
        do {
            renamed = try recording.recording.renamed(to: title)
        } catch {
            throw LibraryError.invalidTitle
        }
        try await repository.updateTitle(id: id, title: renamed.title)
        revision += 1
    }

    /// Replaces the recording's tags. Setting what it already has changes nothing and leaves `revision` alone.
    func setTags(_ tagIDs: Set<UUID>, for id: UUID) async throws {
        let recording = try await existingRecording(id)
        guard recording.tagIDs != tagIDs else {
            return
        }
        try await repository.updateTags(id: id, tagIDs: tagIDs)
        revision += 1
    }

    // MARK: - Tags

    func tags() async throws -> [RecordingTag] {
        try await repository.fetchTags()
    }

    func createTag(named name: String, color: TagColor) async throws {
        let tag = RecordingTag(id: UUID(), name: try RecordingTag.validatedName(name), color: color)
        try await repository.insertTag(tag)
        revision += 1
    }

    func editTag(_ id: UUID, name: String, color: TagColor) async throws {
        try await repository.updateTag(RecordingTag(id: id, name: try RecordingTag.validatedName(name), color: color))
        revision += 1
    }

    /// The recordings keep everything but the tag.
    func deleteTag(_ id: UUID) async throws {
        try await repository.deleteTag(id: id)
        revision += 1
    }

    /// Repoints an existing entry at a file the user chose, after checking the file suits it. Never adds an entry.
    func relocate(_ id: UUID, to url: URL) async throws {
        var recording = try await existingRecording(id)
        let snapshot = try await fileStore.validateReplacement(at: url, for: recording)
        recording.media = snapshot.media
        recording.fileSizeBytes = snapshot.fileSizeBytes
        if let duration = snapshot.duration {
            do {
                recording.recording = try recording.recording.withDuration(duration)
            } catch {
                throw LibraryError.corruptedMedia
            }
        }
        try await repository.update(recording)
        await thumbnails.discardThumbnail(for: id)
        revision += 1
    }

    // MARK: - Removing

    /// Forgets the recording; its files stay exactly where they are. Returns the entry so it can be restored.
    func removeFromLibrary(_ id: UUID) async throws -> LibraryRecording {
        let recording = try await existingRecording(id)
        try await repository.delete(id: id)
        notifyRemoval(of: id, permanently: false)
        await thumbnails.discardThumbnail(for: id)
        revision += 1
        return recording
    }

    /// Any job on the recording ended with its removal, so it must not come back looking queued or running.
    func restore(_ recording: LibraryRecording) async throws {
        var restored = recording
        switch recording.recording.processingStatus {
        case .pending, .transcribing, .indexing:
            restored.recording.processingStatus = recording.hasTranscript ? .ready : .recorded
        case .recorded, .ready, .failed:
            break
        }
        try await repository.insert(restored)
        revision += 1
    }

    /// Moves the recording's files to the Trash, then removes its entry; if the files cannot be moved, the entry stays.
    /// Returns the names of related files left behind.
    func delete(_ id: UUID) async throws -> [String] {
        let recording = try await existingRecording(id)
        let filesLeftBehind = try await fileStore.moveToTrash(recording)
        await thumbnails.discardThumbnail(for: id)
        // Advances once the entry is settled either way, so whoever reloads sees the outcome.
        defer { revision += 1 }
        do {
            try await repository.delete(id: id)
        } catch {
            Self.logger.error("A trashed recording's entry could not be removed: \(String(describing: error))")
            throw LibraryError.entryKeptAfterTrash(detail: String(describing: error))
        }
        notifyRemoval(of: id, permanently: true)
        return filesLeftBehind
    }

    // MARK: - Finder

    func reveal(_ id: UUID) async throws {
        try await fileStore.reveal(existingRecording(id))
    }

    /// Throws `LibraryError.mediaUnavailable(.missing)` when the recording has no transcript file.
    func revealTranscript(of id: UUID) async throws {
        let recording = try await existingRecording(id)
        let inspection = await fileStore.inspect(recording)
        guard let fileName = RecordingFileLayout.transcriptFileName(in: inspection.fileNames) else {
            throw LibraryError.mediaUnavailable(.missing)
        }
        try await fileStore.revealFile(named: fileName, besideMediaOf: recording)
    }

    func openFolder(of id: UUID) async throws {
        try await fileStore.openFolder(of: existingRecording(id))
    }

    func openRecordingsFolder() async throws {
        try await fileStore.openFolder(at: destinations.currentLocation().url)
    }

    private func existingRecording(_ id: UUID) async throws -> LibraryRecording {
        guard let recording = try await repository.fetch(id: id) else {
            throw LibraryError.recordingNotFound
        }
        return recording
    }

    private static let logger = Logger(subsystem: "dev.local.Recorder", category: "Library")
}

extension LibraryService: RecordingsStorageProviding {
    func recordingsStorage() async throws -> RecordingsStorage {
        let location = await recordingsFolder()
        let recordingCount = try await count(matching: RecordingQuery())
        let usedBytes = try await totalFileSize()
        return RecordingsStorage(location: location, recordingCount: recordingCount, usedBytes: usedBytes)
    }
}

/// Lets the Library tell several owners of work about a removal without keeping any of them alive.
private struct WeakRemovalObserver {
    weak var observer: (any RecordingRemovalObserving)?
}
