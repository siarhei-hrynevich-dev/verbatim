import Foundation

/// Fixed sample content for the layout-only Library: the design's recordings, transcript lines for the simulated
/// search, and storage figures. Storage, transcription and indexing are not implemented yet; this stands in for
/// what those services will provide.
struct LibraryPreviewData: Sendable {
    /// A transcript line the simulated search can find. `topics` stands in for the meaning that semantic search
    /// will match.
    struct TranscriptLine: Sendable {
        let recordingID: LibraryItem.ID
        let timestamp: TimeInterval
        let speaker: String
        let text: String
        let topics: String
    }

    let items: [LibraryItem]
    let transcript: [TranscriptLine]
    let storage: LibraryStorage

    /// The design's library. Dates are placed relative to `now`, so the first recordings stay “Today”.
    static func sample(now: Date = .now, calendar: Calendar = .current) -> LibraryPreviewData {
        let items = SampleRecording.all.map { $0.item(relativeTo: now, calendar: calendar) }
        let transcript = SampleLine.all.map { line in
            TranscriptLine(
                recordingID: items[line.recordingIndex].id,
                timestamp: line.timestamp,
                speaker: line.speaker,
                text: line.text,
                topics: line.topics
            )
        }
        return LibraryPreviewData(
            items: items,
            transcript: transcript,
            storage: LibraryStorage(
                folderPath: "~/Movies/Verbatim",
                usedBytes: 18_600_000_000,
                freeBytes: 214_000_000_000
            )
        )
    }
}

/// A sample recording, dated by calendar days relative to today.
private struct SampleRecording {
    let title: String
    let dayOffset: Int
    let hour: Int
    let minute: Int
    let duration: TimeInterval
    let megabytes: Int64
    let kind: LibraryItem.Kind
    let status: LibraryItem.Status

    func item(relativeTo now: Date, calendar: Calendar) -> LibraryItem {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) ?? now
        let recordedAt = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        let folderDate = recordedAt.formatted(
            Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day()
        )
        return LibraryItem(
            id: UUID(),
            title: title,
            recordedAt: recordedAt,
            duration: duration,
            sizeBytes: megabytes * 1_000_000,
            kind: kind,
            status: status,
            folderName: "\(folderDate) \(title)"
        )
    }

    static let all = [
        SampleRecording(
            title: "Architecture Review",
            dayOffset: 0,
            hour: 10,
            minute: 30,
            duration: hms(1, 12, 40),
            megabytes: 3_100,
            kind: .screen,
            status: .ready
        ),
        SampleRecording(
            title: "Weekly Team Sync",
            dayOffset: 0,
            hour: 9,
            minute: 2,
            duration: hms(0, 42, 18),
            megabytes: 1_800,
            kind: .screen,
            status: .transcribing(progress: 0.64)
        ),
        SampleRecording(
            title: "Customer Call — Northwind",
            dayOffset: -1,
            hour: 16,
            minute: 45,
            duration: hms(0, 31, 7),
            megabytes: 28,
            kind: .audio,
            status: .indexing(progress: 0.82)
        ),
        SampleRecording(
            title: "Product Demo",
            dayOffset: -6,
            hour: 14,
            minute: 0,
            duration: hms(0, 24, 51),
            megabytes: 1_100,
            kind: .screen,
            status: .ready
        ),
        SampleRecording(
            title: "1:1 with Maya",
            dayOffset: -6,
            hour: 11,
            minute: 30,
            duration: hms(0, 28, 12),
            megabytes: 24,
            kind: .audio,
            status: .ready
        ),
        SampleRecording(
            title: "Design Critique",
            dayOffset: -7,
            hour: 15,
            minute: 10,
            duration: hms(0, 55, 3),
            megabytes: 2_400,
            kind: .screen,
            status: .failed
        ),
        SampleRecording(
            title: "Onboarding Walkthrough",
            dayOffset: -10,
            hour: 13,
            minute: 20,
            duration: hms(0, 18, 40),
            megabytes: 820,
            kind: .screen,
            status: .recorded
        ),
        SampleRecording(
            title: "Q4 Planning",
            dayOffset: -12,
            hour: 10,
            minute: 0,
            duration: hms(1, 34, 22),
            megabytes: 4_000,
            kind: .screen,
            status: .ready
        ),
        SampleRecording(
            title: "Interview — Backend Engineer",
            dayOffset: -13,
            hour: 15,
            minute: 30,
            duration: hms(0, 47, 55),
            megabytes: 41,
            kind: .audio,
            status: .ready
        ),
        SampleRecording(
            title: "Bug Repro — Export Crash",
            dayOffset: -14,
            hour: 17,
            minute: 5,
            duration: hms(0, 3, 12),
            megabytes: 140,
            kind: .screen,
            status: .missing
        ),
        SampleRecording(
            title: "Sprint Retro",
            dayOffset: -17,
            hour: 16,
            minute: 0,
            duration: hms(0, 38, 20),
            megabytes: 1_600,
            kind: .screen,
            status: .ready
        ),
        SampleRecording(
            title: "Podcast Rough Cut",
            dayOffset: -19,
            hour: 19,
            minute: 40,
            duration: hms(1, 2, 10),
            megabytes: 61,
            kind: .audio,
            status: .ready
        )
    ]

    private static func hms(_ hours: Int, _ minutes: Int, _ seconds: Int) -> TimeInterval {
        TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }
}

/// A sample transcript line, referring to its recording by position in `SampleRecording.all`.
private struct SampleLine {
    let recordingIndex: Int
    let timestamp: TimeInterval
    let speaker: String
    let text: String
    let topics: String

    static let all = [
        SampleLine(
            recordingIndex: 0,
            timestamp: 260,
            speaker: "System Audio",
            text: "I think we should start with the recording engine.",
            topics: "engine recording capture architecture"
        ),
        SampleLine(
            recordingIndex: 0,
            timestamp: 349,
            speaker: "System Audio",
            text: "Then the capture pipeline never competes with transcription.",
            topics: "engine recording capture pipeline"
        ),
        SampleLine(
            recordingIndex: 0,
            timestamp: 74,
            speaker: "You",
            text: "HEVC. ProRes files were too big for hour-long meetings.",
            topics: "encoder video storage"
        ),
        SampleLine(
            recordingIndex: 1,
            timestamp: 767,
            speaker: "You",
            text: "The recording engine is on track for the beta, and the pause bug is fixed.",
            topics: "engine beta recording"
        ),
        SampleLine(
            recordingIndex: 1,
            timestamp: 1_450,
            speaker: "System Audio",
            text: "Can we demo search next week, or is indexing still slow?",
            topics: "search indexing demo"
        ),
        SampleLine(
            recordingIndex: 4,
            timestamp: 75,
            speaker: "System Audio",
            text: "I’d rather own the ScreenCaptureKit side than the search index.",
            topics: "engine capture recording search"
        ),
        SampleLine(
            recordingIndex: 7,
            timestamp: 3_090,
            speaker: "You",
            text: "Budget for the capture rewrite moves to January.",
            topics: "engine capture budget"
        ),
        SampleLine(
            recordingIndex: 3,
            timestamp: 312,
            speaker: "You",
            text: "Hit Start Recording and the window gets out of the way.",
            topics: "recording demo"
        )
    ]
}
