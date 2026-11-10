import Foundation

/// What the model is asked at each stage of a summary. The instructions are in English, which every model in the
/// catalog follows best. Every stage writes in the language chosen in Settings, translating when the recording was in
/// another, so notes and summary agree however many languages were spoken.
enum SummaryPrompts {
    /// Notes on one batch of the transcript.
    static func partNotes(
        lines: String,
        part: Int,
        of total: Int,
        span: ClosedRange<TimeInterval>,
        language: SummaryLanguage
    ) -> [TextGenerationMessage] {
        [
            .system(
                """
                You take notes on one part of a recording's transcript. \(writingRule(language)) \
                List the main points, decisions, figures, names and action items of this part as short bullet \
                points. Use only what the transcript says, without commentary. Reply with the bullet points only.
                """
            ),
            .user("Part \(part) of \(total), \(timeSpan(span)):\n\n\(lines)")
        ]
    }

    /// Notes on several parts at once, when all the notes together are too long for the final summary.
    static func condensedNotes(_ notes: [String], language: SummaryLanguage) -> [TextGenerationMessage] {
        [
            .system(
                """
                You condense notes on consecutive parts of a recording. \(writingRule(language)) Merge \
                them into short bullet points, keeping decisions, figures, names and action items. Use only what the \
                notes say. Reply with the bullet points only.
                """
            ),
            .user(notes.joined(separator: "\n\n"))
        ]
    }

    /// The summary of the whole recording, from the notes on its parts.
    static func finalSummary(_ notes: [String], language: SummaryLanguage) -> [TextGenerationMessage] {
        [
            .system(
                """
                You write the summary of a recording from notes on its parts, given in order. \
                \(writingRule(language)) Start with two or three sentences on what the recording is about. Then \
                give the key points, decisions and action items as bullet points. Be concise, and use only what the \
                notes say. Reply with the summary only.
                """
            ),
            .user(notes.joined(separator: "\n\n"))
        ]
    }

    /// A batch's lines, one per segment, labeled by source only when the recording has more than one.
    static func transcriptLines(_ segments: ArraySlice<TranscriptSegment>, labelsSources: Bool) -> String {
        segments.map { line(for: $0, labelsSource: labelsSources) }.joined(separator: "\n")
    }

    static func line(for segment: TranscriptSegment, labelsSource: Bool) -> String {
        let time = "[\(RecordingClock.timerText(for: segment.startTime))]"
        guard labelsSource, let label = sourceLabel(segment.source) else {
            return "\(time) \(segment.text)"
        }
        return "\(time) \(label): \(segment.text)"
    }

    /// Notes are passed on headed by the span they cover, so the summary keeps their order.
    static func headedNotes(_ text: String, span: ClosedRange<TimeInterval>) -> String {
        "## \(timeSpan(span))\n\(text)"
    }

    /// The model's answer without any reasoning it wrote first, which some models do even when asked not to.
    static func cleaned(_ reply: String) -> String {
        var text = reply
        while let open = text.range(of: "<think>") {
            guard let close = text.range(of: "</think>", range: open.upperBound..<text.endIndex) else {
                text.removeSubrange(open.lowerBound..<text.endIndex)
                break
            }
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sourceLabel(_ source: TranscriptSource) -> String? {
        switch source {
        case .microphone: "Microphone"
        case .systemAudio: "System audio"
        case .unknown: nil
        }
    }

    private static func timeSpan(_ span: ClosedRange<TimeInterval>) -> String {
        "\(RecordingClock.timerText(for: span.lowerBound))–\(RecordingClock.timerText(for: span.upperBound))"
    }

    /// Said at every stage, because small models drift back to the language of what they read.
    static func writingRule(_ language: SummaryLanguage) -> String {
        let name = languageName(language)
        return "Write only in \(name), translating anything said in another language into \(name)."
    }

    /// The language's English name, which models understand better than a code.
    static func languageName(_ language: SummaryLanguage) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: language.code) ?? language.code
    }
}
