import Foundation
import os

/// Finds a recording's media and opens access to it.
///
/// The stored path is tried first, which is the common case and needs no bookmark. Otherwise the bookmark can find a
/// file that moved, and grants access to a folder that is no longer the current recordings folder after a relaunch.
struct MediaFileAccess: Sendable {
    let availability: MediaAvailability
    /// Where the media is, or where it was last known to be.
    let media: MediaReference
    private let scopedURL: URL?

    /// Balance every call with `close()`.
    static func open(_ reference: MediaReference) -> MediaFileAccess {
        let availability = availability(at: reference.url)
        guard availability != .available, let bookmark = reference.bookmark,
            let resolved = resolve(bookmark)
        else {
            return MediaFileAccess(availability: availability, media: reference, scopedURL: nil)
        }
        let isScoped = resolved.url.startAccessingSecurityScopedResource()
        let scopedURL = isScoped ? resolved.url : nil
        // A file put in the Trash by hand is still found by its bookmark, but the user has discarded it.
        guard !isInTrash(resolved.url), self.availability(at: resolved.url) == .available else {
            scopedURL?.stopAccessingSecurityScopedResource()
            return MediaFileAccess(availability: availability, media: reference, scopedURL: nil)
        }
        let newBookmark = resolved.isStale ? bookmarkData(for: resolved.url) : nil
        return MediaFileAccess(
            availability: .available,
            media: MediaReference(url: resolved.url, bookmark: newBookmark ?? bookmark),
            scopedURL: scopedURL
        )
    }

    func close() {
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    /// `nil` when none can be made, which only costs the ability to follow the file or reach it after a relaunch.
    static func bookmarkData(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(options: .withSecurityScope)
        } catch {
            logger.notice("Could not create a bookmark for recording media: \(String(describing: error))")
            return nil
        }
    }

    private static func availability(at url: URL) -> MediaAvailability {
        var status = stat()
        guard stat(url.path(percentEncoded: false), &status) != 0 else {
            return status.st_mode & S_IFMT == S_IFREG ? .available : .missing
        }
        if errno == EACCES || errno == EPERM {
            return .accessDenied
        }
        return isOnUnmountedVolume(url) ? .volumeUnavailable : .missing
    }

    private static func isOnUnmountedVolume(_ url: URL) -> Bool {
        let components = url.pathComponents
        guard components.count > 2, components[1] == "Volumes" else {
            return false
        }
        return !FileManager.default.fileExists(atPath: "/Volumes/\(components[2])")
    }

    private static func isInTrash(_ url: URL) -> Bool {
        url.pathComponents.contains(".Trash") || url.pathComponents.contains(".Trashes")
    }

    private static func resolve(_ bookmark: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI, .withoutMounting],
                bookmarkDataIsStale: &isStale
            )
            return (url, isStale)
        } catch {
            logger.info("A recording's bookmark no longer resolves: \(String(describing: error))")
            return nil
        }
    }

    private static let logger = Logger(subsystem: "dev.local.Recorder", category: "Library")
}
