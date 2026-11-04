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
            case .transcribing, .indexing, .recorded, .failed: return true
            case .ready, .missing: return false
            }
        case .screen:
            return item.kind == .screen
        case .audio:
            return item.kind == .audio
        }
    }
}

enum LibrarySortOrder: Sendable {
    case newestFirst
    case oldestFirst
}
