import Foundation

/// Simulates Library search over the sample transcript, matching the design prototype: titles and transcript
/// lines containing the query are exact matches; lines whose topics contain any query word are related matches,
/// standing in for semantic search. Real full-text and vector search will replace it.
enum SimulatedLibrarySearch {
    static func results(
        for query: String,
        in items: [LibraryItem],
        transcript: [LibraryPreviewData.TranscriptLine]
    ) -> LibrarySearchResults {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let words = normalizedQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !normalizedQuery.isEmpty else {
            return LibrarySearchResults(titleMatches: [], momentGroups: [])
        }

        let titleMatches = items.filter { $0.title.lowercased().contains(normalizedQuery) }

        var exactMoments: [(LibraryItem.ID, LibrarySearchResults.Moment)] = []
        var relatedMoments: [(LibraryItem.ID, LibrarySearchResults.Moment)] = []
        for (index, line) in transcript.enumerated() where items.contains(where: { $0.id == line.recordingID }) {
            if line.text.lowercased().contains(normalizedQuery) {
                exactMoments.append((line.recordingID, moment(from: line, id: index, match: .exact)))
            } else if words.contains(where: line.topics.contains) {
                relatedMoments.append((line.recordingID, moment(from: line, id: index, match: .related)))
            }
        }

        return LibrarySearchResults(
            titleMatches: titleMatches,
            momentGroups: grouped(exactMoments + relatedMoments, items: items)
        )
    }

    private static func moment(
        from line: LibraryPreviewData.TranscriptLine,
        id: Int,
        match: LibrarySearchResults.Match
    ) -> LibrarySearchResults.Moment {
        LibrarySearchResults.Moment(
            id: id,
            timestamp: line.timestamp,
            speaker: line.speaker,
            text: line.text,
            match: match
        )
    }

    /// Groups moments by recording, ordering groups by their best moment.
    private static func grouped(
        _ moments: [(LibraryItem.ID, LibrarySearchResults.Moment)],
        items: [LibraryItem]
    ) -> [LibrarySearchResults.MomentGroup] {
        var order: [LibraryItem.ID] = []
        var momentsByRecording: [LibraryItem.ID: [LibrarySearchResults.Moment]] = [:]
        for (recordingID, moment) in moments {
            if momentsByRecording[recordingID] == nil {
                order.append(recordingID)
            }
            momentsByRecording[recordingID, default: []].append(moment)
        }
        return order.compactMap { recordingID in
            guard let item = items.first(where: { $0.id == recordingID }) else {
                return nil
            }
            return LibrarySearchResults.MomentGroup(item: item, moments: momentsByRecording[recordingID] ?? [])
        }
    }
}
