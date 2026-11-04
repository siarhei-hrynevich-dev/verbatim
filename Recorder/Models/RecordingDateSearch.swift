import Foundation

/// Reads search text as a date, so recordings can be found by when they were made even after being renamed.
///
/// Understands what the Library shows and what people type: `today`, `yesterday`, `2026`, `2026-11`, `2026-11-04`,
/// `Nov`, `November`, `Nov 4` and `Nov 4, 2026`. Dates without a year mean the most recent such date.
struct RecordingDateSearch {
    let now: Date
    var calendar = Calendar.current
    var locale = Locale.current

    func interval(matching text: String) -> DateInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if let relative = relativeDay(trimmed) {
            return relative
        }
        // Formatters take any run of digits as a year, and a number in a search is rarely one unless it looks like one.
        if trimmed.allSatisfy(\.isNumber), trimmed.count != Self.yearDigitCount {
            return nil
        }
        for pattern in Self.patterns {
            guard let date = formatter(pattern.format).date(from: trimmed) else {
                continue
            }
            let anchored = pattern.includesYear ? date : mostRecent(date)
            return calendar.dateInterval(of: pattern.unit, for: anchored)
        }
        return nil
    }

    private func relativeDay(_ text: String) -> DateInterval? {
        if text.compare(String(localized: "Today"), options: .caseInsensitive) == .orderedSame {
            return calendar.dateInterval(of: .day, for: now)
        }
        guard text.compare(String(localized: "Yesterday"), options: .caseInsensitive) == .orderedSame else {
            return nil
        }
        return calendar.date(byAdding: .day, value: -1, to: now).flatMap { calendar.dateInterval(of: .day, for: $0) }
    }

    /// Formatters read a date without a year as being in 2000; moves it to this year, or last year if still ahead.
    private func mostRecent(_ date: Date) -> Date {
        var components = calendar.dateComponents([.month, .day], from: date)
        components.year = calendar.component(.year, from: now)
        guard let thisYear = calendar.date(from: components) else {
            return date
        }
        guard thisYear > now else {
            return thisYear
        }
        return calendar.date(byAdding: .year, value: -1, to: thisYear) ?? thisYear
    }

    private func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    private static let yearDigitCount = 4

    private struct Pattern {
        let format: String
        let unit: Calendar.Component
        let includesYear: Bool
    }

    private static let patterns = [
        Pattern(format: "yyyy-MM-dd", unit: .day, includesYear: true),
        Pattern(format: "yyyy-MM", unit: .month, includesYear: true),
        Pattern(format: "yyyy", unit: .year, includesYear: true),
        Pattern(format: "MMM d, yyyy", unit: .day, includesYear: true),
        Pattern(format: "MMMM d, yyyy", unit: .day, includesYear: true),
        Pattern(format: "MMM d", unit: .day, includesYear: false),
        Pattern(format: "MMMM d", unit: .day, includesYear: false),
        Pattern(format: "MMM", unit: .month, includesYear: false),
        Pattern(format: "MMMM", unit: .month, includesYear: false)
    ]
}
