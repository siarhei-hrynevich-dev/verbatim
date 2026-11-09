import Foundation

/// Persists what the Library knows about recordings. Throws `LibraryError`.
protocol RecordingRepository: Sendable {
    func insert(_ recording: LibraryRecording) async throws
    func fetch(id: UUID) async throws -> LibraryRecording?
    func fetch(matching query: RecordingQuery) async throws -> [LibraryRecording]
    func count(matching query: RecordingQuery) async throws -> Int
    /// The total size of all tracked media, in bytes.
    func totalFileSize() async throws -> Int64
    func updateTitle(id: UUID, title: String) async throws
    /// Replaces which tags a recording carries. Throws `tagNotFound` for a tag that does not exist.
    func updateTags(id: UUID, tagIDs: Set<UUID>) async throws
    /// All tags, in the order they are shown.
    func fetchTags() async throws -> [RecordingTag]
    /// Adds a tag after the others. Throws `duplicateTagName` when another tag has the name, ignoring case.
    func insertTag(_ tag: RecordingTag) async throws
    func updateTag(_ tag: RecordingTag) async throws
    /// Removes the tag from every recording that carries it.
    func deleteTag(id: UUID) async throws
    /// Replaces everything that can change about a recording after it is created.
    func update(_ recording: LibraryRecording) async throws
    func delete(id: UUID) async throws
}

/// The file system and Finder, as far as recordings are concerned. Throws `LibraryError`.
protocol RecordingFileStore: Sendable {
    /// Verifies that finalized media is on disk and reads what the Library stores about it.
    func describeMedia(at url: URL) async throws -> MediaSnapshot
    func inspect(_ recording: LibraryRecording) async -> RecordingFileInspection
    /// Verifies that a user-chosen file can stand in for a recording whose media went missing.
    func validateReplacement(at url: URL, for recording: LibraryRecording) async throws -> MediaSnapshot
    /// Keeps the media reachable until the returned file is closed, for reading that outlasts one call, as playback
    /// does.
    func openMedia(of recording: LibraryRecording) async throws -> OpenMediaFile
    func reveal(_ recording: LibraryRecording) async throws
    /// Reveals a file in the folder of the recording's media.
    func revealFile(named fileName: String, besideMediaOf recording: LibraryRecording) async throws
    func openFolder(of recording: LibraryRecording) async throws
    /// Opens a folder that may not exist yet, creating it first.
    func openFolder(at url: URL) async throws
    /// Moves what belongs to the recording to the Trash, and nothing else. Throws without having moved the media if
    /// it cannot be trashed. Returns the names of related files that could not be moved.
    func moveToTrash(_ recording: LibraryRecording) async throws -> [String]
}

/// Still images of recordings, as encoded image data. Absence is a normal answer: audio has none, and the Library
/// falls back to an icon for media that cannot produce one.
protocol RecordingThumbnailProvider: Sendable {
    func thumbnail(for recording: LibraryRecording) async -> Data?
    func discardThumbnail(for id: UUID) async
}
