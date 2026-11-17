import Foundation

/// Where recordings are saved and how much space they use.
struct LibraryStorage: Equatable, Sendable {
    /// The recordings folder as shown to the user, such as `~/Movies/Verbatim`.
    let folderPath: String
    /// Space used by recordings, transcripts and the search index.
    let usedBytes: Int64
    let freeBytes: Int64

    /// The recordings folder's own name, the root of the path bar.
    var folderName: String {
        (folderPath as NSString).lastPathComponent
    }
}
