import Foundation

/// Summarizes a transcript in batches, so a long recording never has to fit the model's context at once.
///
/// The transcript is split into consecutive batches that fit `batchTokens`, and the model writes notes on each one
/// (map). The notes are then combined into one short summary (reduce); when they are too long for that, they are first
/// condensed in groups, as many rounds as it takes. The notes on each batch are returned as the summary's parts, for
/// later indexing. Depends only on `TextGenerator`, so any backend can write the summary.
struct TranscriptSummarizer: Sendable {
    enum Progress: Equatable, Sendable {
        case writingParts(completed: Int, total: Int)
        case combining
    }

    struct Output: Equatable, Sendable {
        let text: String
        let parts: [SummaryPart]
    }

    let generator: any TextGenerator
    let settings: SummarySettings
    /// What every stage writes in, whatever was spoken.
    let language: SummaryLanguage

    /// Throws `SummaryFailure`, or `CancellationError` once cancelled.
    func summarize(
        _ transcript: Transcript,
        onProgress: @escaping @Sendable (Progress) -> Void
    ) async throws -> Output {
        let segments = transcript.segments
        guard !segments.isEmpty else {
            throw SummaryFailure.emptyTranscript
        }
        let labelsSources = Set(segments.map(\.source)).count > 1
        let lines = segments.map { SummaryPrompts.line(for: $0, labelsSource: labelsSources) }
        var lineTokens: [Int] = []
        for line in lines {
            try Task.checkCancellation()
            lineTokens.append(try await generator.tokenCount(of: line))
        }
        let batches = SummaryBatching.batches(tokenCounts: lineTokens, limit: settings.batchTokens)

        var parts: [SummaryPart] = []
        for (index, batch) in batches.enumerated() {
            onProgress(.writingParts(completed: index, total: batches.count))
            parts.append(try await notes(on: batch, of: segments, position: index, total: batches.count))
        }
        onProgress(.combining)
        let text = try await combine(parts)
        return Output(text: text, parts: parts)
    }

    // MARK: - Map

    private func notes(
        on batch: Range<Int>,
        of segments: [TranscriptSegment],
        position: Int,
        total: Int
    ) async throws -> SummaryPart {
        let slice = segments[batch]
        let span = span(of: slice)
        let labelsSources = Set(segments.map(\.source)).count > 1
        let messages = SummaryPrompts.partNotes(
            lines: SummaryPrompts.transcriptLines(slice, labelsSources: labelsSources),
            part: position + 1,
            of: total,
            span: span,
            language: language
        )
        let text = try await write(messages, maxTokens: settings.batchNoteTokens)
        return SummaryPart(
            position: position,
            startTime: span.lowerBound,
            endTime: span.upperBound,
            firstSegment: batch.lowerBound,
            lastSegment: batch.upperBound - 1,
            text: text
        )
    }

    private func span(of segments: ArraySlice<TranscriptSegment>) -> ClosedRange<TimeInterval> {
        let start = segments.map(\.startTime).min() ?? 0
        let end = segments.map(\.endTime).max() ?? start
        return start...max(start, end)
    }

    // MARK: - Reduce

    /// Condenses notes in groups until they fit one batch, then writes the summary. A round that cannot group anything
    /// (every note alone over the budget) stops condensing rather than looping.
    private func combine(_ parts: [SummaryPart]) async throws -> String {
        var notes = parts.map {
            SummaryPrompts.headedNotes($0.text, span: $0.startTime...$0.endTime)
        }
        while notes.count > 1 {
            var counts: [Int] = []
            for note in notes {
                counts.append(try await generator.tokenCount(of: note))
            }
            let groups = SummaryBatching.batches(tokenCounts: counts, limit: settings.batchTokens)
            guard groups.count > 1, groups.count < notes.count else {
                break
            }
            var condensed: [String] = []
            for group in groups {
                let messages = SummaryPrompts.condensedNotes(Array(notes[group]), language: language)
                condensed.append(try await write(messages, maxTokens: settings.batchNoteTokens))
            }
            notes = condensed
        }
        return try await write(
            SummaryPrompts.finalSummary(notes, language: language),
            maxTokens: settings.summaryTokens
        )
    }

    // MARK: - Writing

    private func write(_ messages: [TextGenerationMessage], maxTokens: Int) async throws -> String {
        try Task.checkCancellation()
        let reply: String
        do {
            reply = try await generator.generate(messages, parameters: parameters(maxTokens: maxTokens))
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as SummaryFailure {
            throw failure
        } catch {
            throw SummaryFailure.generationFailed(detail: error.localizedDescription)
        }
        try Task.checkCancellation()
        let text = SummaryPrompts.cleaned(reply)
        guard !text.isEmpty else {
            throw SummaryFailure.generationFailed(detail: "The model returned no text")
        }
        return text
    }

    private func parameters(maxTokens: Int) -> TextGenerationParameters {
        TextGenerationParameters(
            maxOutputTokens: maxTokens,
            temperature: settings.temperature,
            topP: settings.topP,
            topK: settings.topK,
            repetitionPenalty: settings.repetitionPenalty
        )
    }
}
