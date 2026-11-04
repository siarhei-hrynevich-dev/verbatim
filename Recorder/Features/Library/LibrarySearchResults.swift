import Foundation

/// Results of one Library search: recordings whose titles match, and transcript moments grouped by recording.
struct LibrarySearchResults: Equatable, Sendable {
    enum Match: Sendable {
        /// The line contains the search text.
        case exact
        /// The line matches the meaning of the search, not its words.
        case related
    }

    /// A transcript line that matches the search. Opening it shows the recording at `timestamp`.
    struct Moment: Identifiable, Equatable, Sendable {
        let id: Int
        let timestamp: TimeInterval
        let speaker: String
        let text: String
        let match: Match
    }

    struct MomentGroup: Identifiable, Equatable, Sendable {
        let item: LibraryItem
        let moments: [Moment]

        var id: LibraryItem.ID {
            item.id
        }
    }

    let titleMatches: [LibraryItem]
    let momentGroups: [MomentGroup]

    var momentCount: Int {
        momentGroups.reduce(0) { $0 + $1.moments.count }
    }

    var resultCount: Int {
        titleMatches.count + momentCount
    }
}
