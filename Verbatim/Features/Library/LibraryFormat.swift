import Foundation

/// Text formats for Library values: durations, file sizes, recording dates and counts.
enum LibraryFormat {
    /// `1:12:40` for an hour or more, otherwise `42:18`.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let remainder = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }

    /// A transcript position: `04:20`, or `1:04:20` from the first hour on.
    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        if total >= 3600 {
            return duration(seconds)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// Decimal file sizes as Finder shows them, such as `3.1 GB` or `820 MB`.
    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    /// `Today, 10:30`, `Yesterday, 16:45`, or `Oct 28, 14:00`, with the time in the user's locale.
    static func recordedDate(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Today, \(time)")
        }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)
        if let yesterday, calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday, \(time)")
        }
        return "\(date.formatted(.dateTime.month(.abbreviated).day())), \(time)"
    }

    /// `1 recording`, `12 recordings`.
    static func count(_ value: Int, singular: String, plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }

    /// The path bar and delete sheet list files as `recording.mov · transcript.txt · .srt · .json`: the transcript
    /// formats after the first are shortened to their extensions.
    static func fileSummary(_ fileNames: [String]) -> String {
        var parts: [String] = []
        var hasTranscript = false
        for name in fileNames {
            let isTranscript = name.hasPrefix("transcript.")
            if isTranscript && hasTranscript {
                parts.append(String(name.dropFirst("transcript".count)))
            } else {
                parts.append(name)
            }
            hasTranscript = hasTranscript || isTranscript
        }
        return parts.joined(separator: " · ")
    }
}
