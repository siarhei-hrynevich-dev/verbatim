import Foundation
import os

/// Recordings on the local file system, reached through their stored path or security-scoped bookmark.
///
/// Files are only ever moved to the Trash, never removed. Within a recording folder the app created, only files known
/// to belong to the recording are touched: anything else makes the folder the user's, and it stays.
actor LocalRecordingFileStore: RecordingFileStore {
    /// `.DS_Store` appears whenever a folder is viewed in Finder and says nothing about who owns the folder.
    private static let ignoredFileNames: Set<String> = [".DS_Store"]

    private let systemActions: any SystemActions
    private let trash: @Sendable (URL) throws -> Void

    /// `trash` is replaceable so tests never touch the user's Trash.
    init(
        systemActions: any SystemActions,
        trash: @escaping @Sendable (URL) throws -> Void = { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    ) {
        self.systemActions = systemActions
        self.trash = trash
    }

    // MARK: - Reading

    func describeMedia(at url: URL) throws -> MediaSnapshot {
        let access = MediaFileAccess.open(MediaReference(url: url, bookmark: nil))
        defer { access.close() }
        try require(access)
        return MediaSnapshot(
            media: MediaReference(url: url, bookmark: MediaFileAccess.bookmarkData(for: url)),
            fileSizeBytes: try Self.fileSize(of: url)
        )
    }

    func inspect(_ recording: LibraryRecording) -> RecordingFileInspection {
        let access = MediaFileAccess.open(recording.media)
        defer { access.close() }
        guard access.availability == .available else {
            return RecordingFileInspection(
                availability: access.availability,
                media: recording.media,
                fileNames: [recording.media.url.lastPathComponent],
                trashesFolder: false
            )
        }
        let contents = Self.folderContents(ofMediaAt: access.media.url, recordingID: recording.id)
        return RecordingFileInspection(
            availability: .available,
            media: access.media,
            fileNames: [access.media.url.lastPathComponent] + contents.relatedFileNames,
            trashesFolder: contents.canTrashWholeFolder
        )
    }

    func validateReplacement(at url: URL, for recording: LibraryRecording) async throws -> MediaSnapshot {
        // A file from an open panel is reachable only inside this scope, which is why the bookmark is made here.
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let media: CapturedMedia
        do {
            media = try await MediaValidator.validate(url)
        } catch {
            Self.logger.notice("A chosen file could not be read as media: \(String(describing: error))")
            throw LibraryError.corruptedMedia
        }
        guard media.hasVideo == recording.captureMode.capturesVideo else {
            throw LibraryError.incompatibleMedia
        }
        return MediaSnapshot(
            media: MediaReference(url: url, bookmark: MediaFileAccess.bookmarkData(for: url)),
            fileSizeBytes: media.fileSizeBytes,
            duration: media.duration
        )
    }

    func openMedia(of recording: LibraryRecording) throws -> OpenMediaFile {
        let access = MediaFileAccess.open(recording.media)
        do {
            try require(access)
        } catch {
            access.close()
            throw error
        }
        return OpenMediaFile(url: access.media.url) { access.close() }
    }

    // MARK: - Finder

    func reveal(_ recording: LibraryRecording) async throws {
        try await withMedia(of: recording) { url in
            await systemActions.revealInFinder(url)
        }
    }

    func revealFile(named fileName: String, besideMediaOf recording: LibraryRecording) async throws {
        try await withMedia(of: recording) { url in
            let file = url.deletingLastPathComponent().appending(path: fileName, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else {
                throw LibraryError.mediaUnavailable(.missing)
            }
            await systemActions.revealInFinder(file)
        }
    }

    func openFolder(of recording: LibraryRecording) async throws {
        try await withMedia(of: recording) { url in
            let folder = url.deletingLastPathComponent()
            // Access may cover only the file; revealing the folder in its parent needs no access.
            if await !systemActions.openFile(folder) {
                await systemActions.revealInFinder(folder)
            }
        }
    }

    func openFolder(at url: URL) async throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            Self.logger.error("Could not create the recordings folder: \(String(describing: error))")
            throw LibraryError.folderUnavailable
        }
        guard await systemActions.openFile(url) else {
            throw LibraryError.folderUnavailable
        }
    }

    // MARK: - Trash

    func moveToTrash(_ recording: LibraryRecording) async throws -> [String] {
        try await withMedia(of: recording) { mediaURL in
            let contents = Self.folderContents(ofMediaAt: mediaURL, recordingID: recording.id)
            if contents.canTrashWholeFolder, moveWholeFolder(containing: mediaURL) {
                return []
            }
            do {
                try trash(mediaURL)
            } catch {
                Self.logger.error("Could not move recording media to the Trash: \(String(describing: error))")
                throw LibraryError.trashFailed(detail: error.localizedDescription)
            }
            return moveToTrash(contents.relatedFileNames, besides: mediaURL)
        }
    }

    /// The whole folder goes when possible, so the Trash holds it as the user knew it. Access can turn out to cover
    /// only the media, as for a file located by hand, which leaves moving what can be reached.
    private func moveWholeFolder(containing mediaURL: URL) -> Bool {
        do {
            try trash(mediaURL.deletingLastPathComponent())
            return true
        } catch {
            Self.logger.notice("Could not move a whole recording folder: \(String(describing: error))")
            return false
        }
    }

    private func moveToTrash(_ fileNames: [String], besides mediaURL: URL) -> [String] {
        let folder = mediaURL.deletingLastPathComponent()
        return fileNames.filter { fileName in
            do {
                try trash(folder.appending(path: fileName, directoryHint: .notDirectory))
                return false
            } catch {
                Self.logger.error("A related recording file stayed behind: \(String(describing: error))")
                return true
            }
        }
    }

    // MARK: - Helpers

    /// What a media file's folder holds. Only a folder the app created for this recording can have related files; a
    /// folder that cannot be listed, as when access covers only the media, is treated as holding none.
    private static func folderContents(
        ofMediaAt mediaURL: URL,
        recordingID: UUID
    ) -> (relatedFileNames: [String], canTrashWholeFolder: Bool) {
        let folder = mediaURL.deletingLastPathComponent()
        guard RecordingFileLayout.isOwnedDirectory(named: folder.lastPathComponent, recordingID: recordingID) else {
            return ([], false)
        }
        do {
            let names = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)))
                .subtracting(ignoredFileNames)
                .subtracting([mediaURL.lastPathComponent])
            let related = names.intersection(RecordingFileLayout.derivedFileNames)
            return (related.sorted(), names == related)
        } catch {
            logger.notice("Could not list a recording's folder: \(String(describing: error))")
            return ([], false)
        }
    }

    private func withMedia<Result: Sendable>(
        of recording: LibraryRecording,
        _ body: (URL) async throws -> Result
    ) async throws -> Result {
        let access = MediaFileAccess.open(recording.media)
        defer { access.close() }
        try require(access)
        return try await body(access.media.url)
    }

    private func require(_ access: MediaFileAccess) throws {
        guard access.availability == .available else {
            throw LibraryError.mediaUnavailable(access.availability)
        }
    }

    private static func fileSize(of url: URL) throws -> Int64 {
        do {
            return Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        } catch {
            logger.error("Could not read a recording's size: \(String(describing: error))")
            throw LibraryError.mediaUnavailable(.accessDenied)
        }
    }

    private static let logger = Logger(category: "Library")
}
