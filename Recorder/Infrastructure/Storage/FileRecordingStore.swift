import Foundation
import OSLog

/// The recordings folder on disk, and recording metadata stored as a JSON file beside each recording's media.
///
/// The sidecar stands in until the planned SQLite persistence exists; it keeps metadata out of UserDefaults and
/// with the media it describes. Folders the user picked are reached through a security-scoped bookmark, whose
/// access stays open while that folder is in use.
actor FileRecordingStore: RecordingDestinationStore, RecordingRepository {
    /// UserDefaults is documented as thread-safe, but is not marked Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let defaultFolder: URL
    private var scopedFolder: URL?

    init(defaults: UserDefaults, defaultFolder: URL) {
        self.defaults = defaults
        self.defaultFolder = defaultFolder
    }

    /// `~/Movies/Verbatim` in the real home directory; inside the sandbox, `NSHomeDirectory()` is the container.
    /// The Movies entitlement grants access to it.
    static func defaultFolder() -> URL {
        realHomeDirectory().appending(path: "Movies/Verbatim", directoryHint: .isDirectory)
    }

    // MARK: - RecordingDestinationStore

    func currentLocation() -> RecordingLocation {
        let url = resolvedFolder()
        return RecordingLocation(
            url: url,
            displayPath: Self.displayPath(of: url),
            availableBytes: Self.availableBytes(at: url),
            isAccessible: Self.isAccessible(url)
        )
    }

    func prepareDestination(id: UUID, createdAt: Date) throws -> RecordingDestination {
        let folder = resolvedFolder()
        let directoryName = RecordingFileLayout.directoryName(createdAt: createdAt, id: id)
        let directoryURL = folder.appending(path: directoryName, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Without intermediate directories, creation fails rather than reusing an existing folder.
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)
        } catch {
            throw RecordingFailure.destinationUnavailable(
                path: Self.displayPath(of: folder),
                detail: error.localizedDescription
            )
        }
        return RecordingDestination(
            directoryURL: directoryURL,
            mediaURL: directoryURL.appending(path: RecordingFileLayout.mediaFileName, directoryHint: .notDirectory)
        )
    }

    func discardIfEmpty(_ destination: RecordingDestination) -> Bool {
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: destination.directoryURL.path)
            guard contents.isEmpty else {
                return false
            }
            try FileManager.default.removeItem(at: destination.directoryURL)
            return true
        } catch {
            Self.logger.error("Could not remove an empty recording folder: \(String(describing: error))")
            return false
        }
    }

    func useFolder(_ url: URL) throws {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let bookmark = try url.bookmarkData(options: .withSecurityScope)
        defaults.set(bookmark, forKey: Self.folderBookmarkKey)
        defaults.set(url.path(percentEncoded: false), forKey: Self.folderPathKey)
        endFolderAccess()
    }

    func useDefaultFolder() {
        defaults.removeObject(forKey: Self.folderBookmarkKey)
        defaults.removeObject(forKey: Self.folderPathKey)
        endFolderAccess()
    }

    // MARK: - RecordingRepository

    func save(_ metadata: RecordingMetadata, in destination: RecordingDestination) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = destination.directoryURL.appending(
            path: RecordingFileLayout.metadataFileName,
            directoryHint: .notDirectory
        )
        try encoder.encode(metadata).write(to: url, options: .atomic)
    }

    // MARK: - Folder access

    /// A chosen folder that can no longer be reached stays selected, so it surfaces as inaccessible rather than
    /// recordings silently going elsewhere.
    private func resolvedFolder() -> URL {
        guard let bookmark = defaults.data(forKey: Self.folderBookmarkKey) else {
            return defaultFolder
        }
        if let scopedFolder {
            return scopedFolder
        }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                bookmarkDataIsStale: &isStale
            )
            guard url.startAccessingSecurityScopedResource() else {
                Self.logger.error("Access to the chosen recordings folder was refused")
                return url
            }
            scopedFolder = url
            if isStale {
                defaults.set(try url.bookmarkData(options: .withSecurityScope), forKey: Self.folderBookmarkKey)
            }
            return url
        } catch {
            Self.logger.error("Could not resolve the recordings folder bookmark: \(String(describing: error))")
            let path = defaults.string(forKey: Self.folderPathKey) ?? defaultFolder.path(percentEncoded: false)
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    private func endFolderAccess() {
        scopedFolder?.stopAccessingSecurityScopedResource()
        scopedFolder = nil
    }

    /// The folder is created on first use, so what must be writable is the nearest part of the path that exists.
    private static func isAccessible(_ url: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: nearestExistingFolder(of: url).path(percentEncoded: false))
    }

    private static func nearestExistingFolder(of url: URL) -> URL {
        var existing = url
        while !FileManager.default.fileExists(atPath: existing.path(percentEncoded: false)), existing.path != "/" {
            existing = existing.deletingLastPathComponent()
        }
        return existing
    }

    private static func availableBytes(at url: URL) -> Int64 {
        do {
            let values = try nearestExistingFolder(of: url).resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey
            ])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            logger.error("Could not read free disk space: \(String(describing: error))")
            return 0
        }
    }

    private static func displayPath(of url: URL) -> String {
        let path = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let home = realHomeDirectory().path(percentEncoded: false)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path == home {
            return "~"
        }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : "/" + path
    }

    private static func realHomeDirectory() -> URL {
        guard let passwordEntry = getpwuid(getuid()), let directory = passwordEntry.pointee.pw_dir else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    }

    private static let folderBookmarkKey = "recording.folderBookmark"
    private static let folderPathKey = "recording.folderPath"
    private static let logger = Logger(subsystem: "dev.local.Recorder", category: "Storage")
}
