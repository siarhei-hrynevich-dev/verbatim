import CoreMedia
import Foundation

@testable import Recorder

/// A throwaway library on disk: a real database and real files in a temporary folder. Only the side effects that would
/// reach outside the folder are replaced: Finder, and the Trash, which becomes a folder that can be inspected.
final class LibraryTestEnvironment: Sendable {
    let root: URL
    let recordingsFolder: URL
    let trashFolder: URL
    let databaseURL: URL
    let finder = FinderSpy()
    let thumbnails: VideoThumbnailProvider

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "LibraryTests-\(UUID())",
            directoryHint: .isDirectory
        )
        recordingsFolder = root.appending(path: "Verbatim", directoryHint: .isDirectory)
        trashFolder = root.appending(path: "TrashFolder", directoryHint: .isDirectory)
        databaseURL = root.appending(path: "Support/Library.sqlite")
        thumbnails = VideoThumbnailProvider(
            cacheFolder: root.appending(path: "Thumbnails", directoryHint: .isDirectory)
        )
        try FileManager.default.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trashFolder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func makeRepository(now: @escaping @Sendable () -> Date = { .now }) -> SQLiteRecordingRepository {
        SQLiteRecordingRepository(databaseURL: databaseURL, now: now)
    }

    func makeFileStore() -> LocalRecordingFileStore {
        let trashFolder = trashFolder
        return LocalRecordingFileStore(systemActions: finder) { url in
            let destination = trashFolder.appending(path: "\(UUID())-\(url.lastPathComponent)")
            try FileManager.default.moveItem(at: url, to: destination)
        }
    }

    @MainActor
    func makeService(
        repository: (any RecordingRepository)? = nil,
        fileStore: (any RecordingFileStore)? = nil
    ) -> LibraryService {
        LibraryService(
            repository: repository ?? makeRepository(),
            fileStore: fileStore ?? makeFileStore(),
            thumbnails: thumbnails,
            destinations: FixedDestination(folder: recordingsFolder)
        )
    }

    /// A folder laid out as the recorder leaves it, holding a stand-in media file and the sidecar.
    func makeRecordingFolder(id: UUID = UUID(), createdAt: Date = .now) throws -> RecordingDestination {
        let name = RecordingFileLayout.directoryName(createdAt: createdAt, id: id)
        let directory = recordingsFolder.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let media = directory.appending(path: RecordingFileLayout.mediaFileName)
        try Data(repeating: 7, count: 2_048).write(to: media)
        try Data("{}".utf8).write(to: directory.appending(path: RecordingFileLayout.metadataFileName))
        return RecordingDestination(directoryURL: directory, mediaURL: media)
    }

    /// An entry whose media is on disk, ready to insert.
    func makeRecording(
        title: String = "Demo",
        createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        duration: TimeInterval = 60,
        mode: CaptureMode = .screen,
        id: UUID = UUID()
    ) throws -> LibraryRecording {
        let destination = try makeRecordingFolder(id: id, createdAt: createdAt)
        return try LibraryRecording(
            recording: Recording(
                id: id,
                title: title,
                createdAt: createdAt,
                duration: duration,
                processingStatus: .recorded
            ),
            captureMode: mode,
            media: MediaReference(
                url: destination.mediaURL,
                bookmark: MediaFileAccess.bookmarkData(for: destination.mediaURL)
            ),
            fileSizeBytes: 2_048
        )
    }

    /// Writes playable media with the real writer. Video for `hasVideo`, otherwise microphone audio only.
    func writePlayableMedia(named name: String = "located.mov", hasVideo: Bool) async throws -> URL {
        let url = root.appending(path: "\(UUID())-\(name)")
        let writer = try MediaFileWriter(
            url: url,
            video: hasVideo ? .init(size: PixelSize(width: 320, height: 180), frameRate: .fps30) : nil,
            audioSources: [.microphone]
        )
        for index in 0..<30 {
            let time = CMTime(seconds: 10 + Double(index) / 30, preferredTimescale: 48_000)
            if hasVideo {
                writer.appendVideoFrame(try SyntheticSamples.videoFrame(at: time))
            }
        }
        for index in 0..<10 {
            let time = CMTime(seconds: 10 + Double(index) / 10, preferredTimescale: 48_000)
            writer.appendAudio(try SyntheticSamples.audio(at: time, channels: 1, seconds: 0.1), from: .microphone)
        }
        try await writer.finish(stopTime: CMTime(seconds: 11, preferredTimescale: 48_000))
        return url
    }

    func trashedItemNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: trashFolder.path(percentEncoded: false)).sorted()
    }
}

/// Records what would have been asked of Finder.
actor FinderSpyState {
    private(set) var revealed: [URL] = []
    private(set) var opened: [URL] = []
    var opensSucceed = true

    func reveal(_ url: URL) { revealed.append(url) }
    func open(_ url: URL) -> Bool {
        opened.append(url)
        return opensSucceed
    }
    func setOpensSucceed(_ value: Bool) { opensSucceed = value }
}

struct FinderSpy: SystemActions {
    let state = FinderSpyState()

    func open(_ pane: SystemSettingsPane) async {}
    func openInFinder(_ url: URL) async {}
    func revealInFinder(_ url: URL) async { await state.reveal(url) }
    func openFile(_ url: URL) async -> Bool { await state.open(url) }
}

/// A recordings folder that never changes.
struct FixedDestination: RecordingDestinationStore {
    let folder: URL

    func currentLocation() async -> RecordingLocation {
        RecordingLocation(url: folder, displayPath: "~/Verbatim", availableBytes: 1_000_000, isAccessible: true)
    }
    func prepareDestination(id: UUID, createdAt: Date) async throws -> RecordingDestination {
        throw TestError.failed
    }
    func discardIfEmpty(_ destination: RecordingDestination) async -> Bool { false }
    func useFolder(_ url: URL) async throws {}
    func useDefaultFolder() async {}
}

/// The real file store, except that moving to the Trash fails for the media or for chosen related files.
struct TrashFailingFileStore: RecordingFileStore {
    let base: LocalRecordingFileStore

    func describeMedia(at url: URL) async throws -> MediaSnapshot { try await base.describeMedia(at: url) }
    func inspect(_ recording: LibraryRecording) async -> RecordingFileInspection { await base.inspect(recording) }
    func validateReplacement(at url: URL, for recording: LibraryRecording) async throws -> MediaSnapshot {
        try await base.validateReplacement(at: url, for: recording)
    }
    func openMedia(of recording: LibraryRecording) async throws -> OpenMediaFile {
        try await base.openMedia(of: recording)
    }
    func reveal(_ recording: LibraryRecording) async throws { try await base.reveal(recording) }
    func revealFile(named fileName: String, besideMediaOf recording: LibraryRecording) async throws {
        try await base.revealFile(named: fileName, besideMediaOf: recording)
    }
    func openFolder(of recording: LibraryRecording) async throws { try await base.openFolder(of: recording) }
    func openFolder(at url: URL) async throws { try await base.openFolder(at: url) }
    func moveToTrash(_ recording: LibraryRecording) async throws -> [String] {
        throw LibraryError.trashFailed(detail: "The volume is read-only.")
    }
}

/// A database that always fails, as when the disk is full. Reading works, so an entry can be found to act on.
struct WriteFailingRepository: RecordingRepository {
    let base: SQLiteRecordingRepository
    private let failure = LibraryError.persistenceFailed(detail: "disk full")

    func insert(_ recording: LibraryRecording) async throws { throw failure }
    func fetch(id: UUID) async throws -> LibraryRecording? { try await base.fetch(id: id) }
    func fetch(matching query: RecordingQuery) async throws -> [LibraryRecording] {
        try await base.fetch(matching: query)
    }
    func count(matching query: RecordingQuery) async throws -> Int { try await base.count(matching: query) }
    func totalFileSize() async throws -> Int64 { try await base.totalFileSize() }
    func updateTitle(id: UUID, title: String) async throws { throw failure }
    func update(_ recording: LibraryRecording) async throws { throw failure }
    func delete(id: UUID) async throws { throw failure }
}
