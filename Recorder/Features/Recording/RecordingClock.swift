import Foundation

/// Elapsed recording time that excludes paused intervals. Time is passed in explicitly, so views can
/// render it from a timeline and tests stay deterministic.
struct RecordingClock: Equatable, Sendable {
    private let startedAt: Date
    private var pausedAt: Date?
    private var pausedDuration: TimeInterval = 0

    init(startedAt: Date) {
        self.startedAt = startedAt
    }

    var isPaused: Bool {
        pausedAt != nil
    }

    func elapsed(at date: Date) -> TimeInterval {
        let end = pausedAt ?? date
        return max(0, end.timeIntervalSince(startedAt) - pausedDuration)
    }

    mutating func pause(at date: Date) {
        guard pausedAt == nil else {
            return
        }
        pausedAt = date
    }

    mutating func resume(at date: Date) {
        guard let pausedAt else {
            return
        }
        pausedDuration += max(0, date.timeIntervalSince(pausedAt))
        self.pausedAt = nil
    }

    /// Formats elapsed time as `HH:MM:SS`, as shown by the recording timer.
    static func timerText(for elapsed: TimeInterval) -> String {
        let totalSeconds = Int(max(0, elapsed))
        let hours = totalSeconds / 3600
        let minutes = totalSeconds % 3600 / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
