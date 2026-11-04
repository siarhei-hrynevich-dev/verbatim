import Foundation

/// A Library problem as the user reads it: what happened, and what it means for their files.
struct LibraryIssue: Equatable, Sendable {
    let title: String
    let message: String

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    init(_ error: any Error) {
        guard let error = error as? LibraryError else {
            self.init(title: String(localized: "Something went wrong"), message: error.localizedDescription)
            return
        }
        self.init(error)
    }

    private init(_ error: LibraryError) {
        switch error {
        case .databaseUnavailable, .databaseMigrationFailed, .persistenceFailed, .entryKeptAfterTrash,
            .databaseFromNewerVersion:
            self = Self.database(error)
        case .mediaUnavailable(let availability):
            self = Self.media(availability)
        case .recordingNotFound:
            self.init(
                title: String(localized: "Recording not found"),
                message: String(localized: "It’s no longer in the Library.")
            )
        case .invalidTitle:
            self.init(
                title: String(localized: "A recording needs a name"),
                message: String(localized: "Enter a name with at least one visible character.")
            )
        case .corruptedMedia:
            self.init(
                title: String(localized: "This file can’t be used"),
                message: String(localized: "It isn’t playable media, or it’s damaged. The recording wasn’t changed.")
            )
        case .incompatibleMedia:
            self.init(
                title: String(localized: "This isn’t the same kind of recording"),
                message: String(localized: "Choose a file with the same kind of content: video or audio only.")
            )
        case .alreadyInLibrary:
            self.init(
                title: String(localized: "This file is already in the Library"),
                message: String(localized: "Another recording already uses this file.")
            )
        case .trashFailed(let detail):
            self.init(
                title: String(localized: "Couldn’t move the recording to the Trash"),
                message: String(localized: "It stays in the Library and on disk. \(detail)")
            )
        case .folderUnavailable:
            self.init(
                title: String(localized: "The recordings folder isn’t available"),
                message: String(
                    localized: "Check that its drive is connected, or choose another folder in the Recorder."
                )
            )
        case .openFailed:
            self.init(
                title: String(localized: "Couldn’t open the recording"),
                message: String(localized: "macOS found no application able to open this file.")
            )
        }
    }

    private static func database(_ error: LibraryError) -> LibraryIssue {
        switch error {
        case .databaseFromNewerVersion:
            LibraryIssue(
                title: String(localized: "The Library needs a newer Verbatim"),
                message: String(localized: "It was last used by a newer version. Your recordings are untouched.")
            )
        case .entryKeptAfterTrash:
            LibraryIssue(
                title: String(localized: "The recording is in the Trash, but still listed"),
                message: String(localized: "Its Library entry couldn’t be removed. Use Remove from Library to retry.")
            )
        case .databaseUnavailable(let detail), .databaseMigrationFailed(let detail), .persistenceFailed(let detail):
            LibraryIssue(
                title: String(localized: "The Library couldn’t be updated"),
                message: String(localized: "Your recordings are safe on disk. \(detail)")
            )
        default:
            LibraryIssue(title: String(localized: "Something went wrong"), message: String(describing: error))
        }
    }

    private static func media(_ availability: MediaAvailability) -> LibraryIssue {
        switch availability {
        case .volumeUnavailable:
            LibraryIssue(
                title: String(localized: "The drive isn’t connected"),
                message: String(localized: "Connect the drive holding this recording, then try again.")
            )
        case .accessDenied:
            LibraryIssue(
                title: String(localized: "Verbatim doesn’t have access to this file"),
                message: String(localized: "Use Locate File to choose it and grant access.")
            )
        case .missing, .available:
            LibraryIssue(
                title: String(localized: "The file is missing"),
                message: String(localized: "It may have been moved or deleted in Finder. Use Locate File to find it.")
            )
        }
    }

    /// The recording left the Library, but files beside its media could not be moved with it.
    static func filesLeftBehind(_ fileNames: [String]) -> LibraryIssue {
        LibraryIssue(
            title: String(localized: "Some files stayed behind"),
            message: String(
                localized:
                    "The recording is in the Trash, but these couldn’t be moved: \(fileNames.joined(separator: ", "))"
            )
        )
    }
}
