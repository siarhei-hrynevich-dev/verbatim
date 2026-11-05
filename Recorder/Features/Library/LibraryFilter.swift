import Foundation

/// A sidebar section of the Library, each showing a subset of recordings.
enum LibraryFilter: CaseIterable, Hashable, Sendable {
    case all
    case recent
    case processing
    case screen
    case audio

    /// Recordings from today and the six days before it count as recent.
    static let recentDayCount = 7

    func includes(_ item: LibraryItem, now: Date, calendar: Calendar) -> Bool {
        switch self {
        case .all:
            return true
        case .recent:
            let startOfToday = calendar.startOfDay(for: now)
            guard let start = calendar.date(byAdding: .day, value: 1 - Self.recentDayCount, to: startOfToday) else {
                return false
            }
            return item.recordedAt >= start
        case .processing:
            switch item.status {
            case .pending, .transcribing, .indexing: return true
            case .recorded, .failed: return item.canStartProcessing
            case .ready, .missing: return false
            }
        case .screen:
            return item.kind != .audio
        case .audio:
            return item.kind == .audio
        }
    }

    /// The same section as a database query, for a recent cutoff computed from `now`.
    func query(now: Date, calendar: Calendar) -> RecordingQuery {
        var query = RecordingQuery()
        switch self {
        case .all:
            break
        case .recent:
            query.createdSince = calendar.date(
                byAdding: .day,
                value: 1 - Self.recentDayCount,
                to: calendar.startOfDay(for: now)
            )
        case .processing:
            query.statuses = [.pending, .transcribing, .indexing, .failed]
        case .screen:
            query.captureModes = [.screen, .window]
        case .audio:
            query.captureModes = [.audioOnly]
        }
        return query
    }
}
