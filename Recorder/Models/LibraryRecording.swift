import Foundation

/// Where a recording's media is. The path is what the Library shows and tries first; the bookmark keeps access to
/// folders outside the sandbox across launches and follows the file when it is moved or renamed in Finder.
struct MediaReference: Equatable, Sendable {
    var url: URL
    var bookmark: Data?
}

/// A recording the Library tracks. Identity is the recording's identifier, never its title or file name, and the title
/// is independent of the file path.
struct LibraryRecording: Identifiable, Equatable, Sendable {
    var recording: Recording
    let captureMode: CaptureMode
    var media: MediaReference
    var fileSizeBytes: Int64

    var id: UUID {
        recording.id
    }
}

/// The order of a recordings list.
enum RecordingSortOrder: CaseIterable, Sendable {
    case newestFirst
    case oldestFirst
    case name
    /// Longest first.
    case duration
}

/// Which recordings to list, and how. Empty conditions do not restrict the result.
struct RecordingQuery: Equatable, Sendable {
    /// Matches recordings by title or, when the text reads as a date, by when they were recorded.
    struct Search: Equatable, Sendable {
        let text: String
        var recordedDuring: DateInterval?
    }

    var captureModes: [CaptureMode] = []
    var statuses: [Recording.ProcessingStatus] = []
    var createdSince: Date?
    var search: Search?
    var sortOrder = RecordingSortOrder.newestFirst
}

/// Whether a recording's media can be reached right now. Anything but `available` keeps the Library entry.
enum MediaAvailability: Equatable, Sendable {
    case available
    /// Moved, renamed or deleted, and not found through its bookmark.
    case missing
    /// It lives on an external volume that is not mounted.
    case volumeUnavailable
    /// It exists, but the app is not allowed to reach it.
    case accessDenied
}

/// What the file system says about one recording.
struct RecordingFileInspection: Equatable, Sendable {
    let availability: MediaAvailability
    /// Differs from the recording's stored reference when the file moved or its bookmark needed refreshing.
    let media: MediaReference
    /// The media and related files in its folder that belong to the recording, media first.
    let fileNames: [String]
    /// Whether deleting moves the whole recording folder, rather than individual files, to the Trash.
    let trashesFolder: Bool
}

/// A media file that passed the checks for being tracked by the Library.
struct MediaSnapshot: Equatable, Sendable {
    let media: MediaReference
    let fileSizeBytes: Int64
    /// Known only when the file was opened as media.
    var duration: TimeInterval?
}

/// Failures of the Library's persistence and file operations.
enum LibraryError: Error, Equatable, Sendable {
    case databaseUnavailable(detail: String)
    case databaseMigrationFailed(detail: String)
    /// The database was written by a newer version of the app; it is left untouched.
    case databaseFromNewerVersion
    case persistenceFailed(detail: String)
    case recordingNotFound
    case invalidTitle
    case mediaUnavailable(MediaAvailability)
    case corruptedMedia
    /// The file chosen for a recording does not have that recording's kind of content.
    case incompatibleMedia
    /// Another Library entry already refers to the file.
    case alreadyInLibrary
    case trashFailed(detail: String)
    /// The files are in the Trash, but the entry could not be removed; it will show as missing.
    case entryKeptAfterTrash(detail: String)
    case folderUnavailable
    case openFailed
}
