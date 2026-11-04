import Foundation

/// Fixed sample content for the layout-only Viewer: the design's transcripts and the Library's sample recordings.
/// Media playback and transcription are not implemented yet; this stands in for what they will provide.
struct ViewerPreviewData: Sendable {
    let library: LibraryPreviewData
    let screenTranscript: [TranscriptLine]
    let audioTranscript: [TranscriptLine]

    static func sample(now: Date = .now, calendar: Calendar = .current) -> ViewerPreviewData {
        ViewerPreviewData(
            library: .sample(now: now, calendar: calendar),
            screenTranscript: numbered(architectureReview),
            audioTranscript: numbered(oneOnOne)
        )
    }

    /// The Viewer's view of a Library recording, with a transcript state that follows its Library status.
    func recording(for item: LibraryItem) -> ViewerRecording {
        let transcript = item.kind == .audio ? audioTranscript : screenTranscript
        return ViewerRecording(
            item: item,
            transcript: transcript,
            transcriptState: Self.transcriptState(for: item.status),
            language: String(localized: "English")
        )
    }

    func item(titled title: String) -> LibraryItem? {
        library.items.first { $0.title == title }
    }

    private static func transcriptState(for status: LibraryItem.Status) -> ViewerRecording.TranscriptState {
        switch status {
        case .ready, .indexing, .missing: .ready
        case .transcribing(let progress): .processing(progress: progress)
        case .failed: .failed(stoppedAt: failurePosition)
        case .recorded: .notProcessed
        }
    }

    /// The design's failed recording stops at 00:31:40.
    private static let failurePosition: TimeInterval = 1_900

    private static func numbered(_ lines: [RawLine]) -> [TranscriptLine] {
        lines.enumerated().map { index, line in
            TranscriptLine(id: index, start: line.start, speaker: line.speaker, text: line.text)
        }
    }
}

private struct RawLine {
    let start: TimeInterval
    let speaker: TranscriptLine.Speaker
    let text: String
}

private let architectureReview = [
    RawLine(start: 0, speaker: .you, text: "Okay, I think everyone’s here. Let’s give it a minute for Priya."),
    RawLine(start: 9, speaker: .systemAudio, text: "I’m here, just switching rooms. Go ahead."),
    RawLine(
        start: 21,
        speaker: .you,
        text: "Great. Today is only about the recorder architecture, nothing on the library UI."
    ),
    RawLine(start: 38, speaker: .systemAudio, text: "Do we have the notes from last week’s spike?"),
    RawLine(
        start: 47,
        speaker: .you,
        text: "They’re in the shared doc. Short version: capture works, the encoder was the bottleneck."
    ),
    RawLine(start: 66, speaker: .systemAudio, text: "Was that the HEVC path or ProRes?"),
    RawLine(start: 74, speaker: .you, text: "HEVC. ProRes files were too big for hour-long meetings."),
    RawLine(start: 95, speaker: .systemAudio, text: "Makes sense. What about audio drift?"),
    RawLine(
        start: 104,
        speaker: .you,
        text: "We saw about forty milliseconds over an hour. Acceptable, but I want it lower."
    ),
    RawLine(start: 131, speaker: .systemAudio, text: "We could resample the system track against the mic clock."),
    RawLine(start: 150, speaker: .you, text: "Let’s try that. Priya, can you own it?"),
    RawLine(start: 158, speaker: .systemAudio, text: "Sure, I’ll have numbers by Thursday."),
    RawLine(
        start: 176,
        speaker: .you,
        text: "Next is storage. Every recording gets its own folder with the movie and the transcript files."
    ),
    RawLine(start: 203, speaker: .systemAudio, text: "And the database only keeps paths and the index?"),
    RawLine(
        start: 212,
        speaker: .you,
        text: "Exactly. If someone moves a folder in Finder, we mark it missing and ask them to locate it."
    ),
    RawLine(start: 252, speaker: .you, text: "Let’s discuss the architecture of the new application."),
    RawLine(start: 260, speaker: .systemAudio, text: "I think we should start with the recording engine."),
    RawLine(start: 268, speaker: .you, text: "That makes sense. We can use ScreenCaptureKit."),
    RawLine(
        start: 281,
        speaker: .systemAudio,
        text: "One stream for video, and separate tracks for the mic and system audio."
    ),
    RawLine(
        start: 297,
        speaker: .you,
        text: "Separate tracks also give us the You and System Audio labels in the transcript."
    ),
    RawLine(start: 318, speaker: .systemAudio, text: "Whisper doesn’t run during recording, right?"),
    RawLine(
        start: 326,
        speaker: .you,
        text: "Right. Models load only after you stop, and processing pauses if a new recording starts."
    ),
    RawLine(start: 349, speaker: .systemAudio, text: "Then the capture pipeline never competes with transcription."),
    RawLine(start: 362, speaker: .you, text: "That’s the whole point. Recording first, everything else after."),
    RawLine(start: 380, speaker: .systemAudio, text: "What’s the fallback if transcription fails halfway?"),
    RawLine(
        start: 391,
        speaker: .you,
        text: "The file is already saved. We show Failed in the library with a Retry button."
    ),
    RawLine(start: 412, speaker: .systemAudio, text: "Good. And search covers titles, full text and meaning?"),
    RawLine(start: 421, speaker: .you, text: "One field for all three. Results jump straight to the timestamp."),
    RawLine(start: 440, speaker: .systemAudio, text: "Then I think we’re done with the engine. Library next week?")
]

private let oneOnOne = [
    RawLine(start: 0, speaker: .you, text: "Hey, thanks for making time. How’s the first month going?"),
    RawLine(
        start: 7,
        speaker: .systemAudio,
        text: "Honestly better than I expected. The codebase is smaller than I thought."
    ),
    RawLine(start: 19, speaker: .you, text: "Good. Anything that’s slowing you down?"),
    RawLine(start: 26, speaker: .systemAudio, text: "Builds, mostly. A clean build takes about six minutes."),
    RawLine(start: 41, speaker: .you, text: "We can look at caching. I’ll ask Sam to pair with you on it."),
    RawLine(start: 55, speaker: .systemAudio, text: "That would help. I also wanted to talk about what I own next."),
    RawLine(start: 68, speaker: .you, text: "Sure. What are you leaning towards?"),
    RawLine(start: 75, speaker: .systemAudio, text: "I’d rather own the ScreenCaptureKit side than the search index."),
    RawLine(start: 92, speaker: .you, text: "That works. The capture code needs someone full time anyway."),
    RawLine(start: 106, speaker: .systemAudio, text: "Is there a doc for the current pipeline?"),
    RawLine(
        start: 114,
        speaker: .you,
        text: "There’s an outline. Write down what’s missing as you go and we’ll review it Friday."
    ),
    RawLine(start: 131, speaker: .systemAudio, text: "Will do."),
    RawLine(start: 136, speaker: .you, text: "Last thing: take the Thursday off you asked about. It’s fine.")
]
