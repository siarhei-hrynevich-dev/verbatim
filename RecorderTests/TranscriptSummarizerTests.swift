import Foundation
import Synchronization
import Testing

@testable import Recorder

struct TranscriptSummarizerTests {
    private let generator = FakeTextGenerator()

    private func summarize(
        _ transcript: Transcript,
        batchTokens: Int,
        language: SummaryLanguage = SummaryFixtures.russian,
        progress: ProgressLog = ProgressLog()
    ) async throws -> TranscriptSummarizer.Output {
        let summarizer = TranscriptSummarizer(
            generator: generator,
            settings: SummaryFixtures.settings(batchTokens: batchTokens),
            language: language
        )
        return try await summarizer.summarize(transcript) { update in
            progress.updates.withLock { $0.append(update) }
        }
    }

    /// Every line is "[mm:ss] Source: " plus ten words: twelve tokens for the fake generator.
    @Test func aLongTranscriptIsSummarizedInBatchesThenCombined() async throws {
        let transcript = SummaryFixtures.transcript(of: UUID(), lines: 10)
        let progress = ProgressLog()

        let output = try await summarize(transcript, batchTokens: 50, progress: progress)

        // Four lines of twelve tokens fit fifty: batches of 4, 4 and 2 lines, then one final summary.
        #expect(output.parts.map(\.firstSegment) == [0, 4, 8])
        #expect(output.parts.map(\.lastSegment) == [3, 7, 9])
        #expect(output.parts.map(\.startTime) == [0, 40, 80])
        #expect(output.parts.map(\.endTime) == [35, 75, 95])
        #expect(output.parts.map(\.text) == ["notes 1", "notes 2", "notes 3"])
        #expect(output.text == "summary 4")
        #expect(
            progress.updates.withLock { $0 } == [
                .writingParts(completed: 0, total: 3),
                .writingParts(completed: 1, total: 3),
                .writingParts(completed: 2, total: 3),
                .combining
            ]
        )
    }

    @Test func promptsCarryTheLinesTheLanguageAndTheLimits() async throws {
        let transcript = SummaryFixtures.transcript(of: UUID(), lines: 2)

        _ = try await summarize(transcript, batchTokens: 1_000)

        let requests = generator.read(\.requests)
        let parameters = generator.read(\.parameters)
        let preset = LanguageModelCatalog.curated[1].preset
        #expect(requests.count == 2)
        #expect(requests[0][0].content.contains("Write only in Russian"))
        #expect(requests[0][1].content.contains("[00:00:00] Microphone: word0"))
        #expect(requests[0][1].content.contains("[00:00:10] System audio: word1"))
        #expect(requests[1][1].content.contains("## 00:00:00–00:00:15\nnotes 1"))
        #expect(parameters.map(\.maxOutputTokens) == [preset.batchNoteTokens, preset.summaryTokens])
        #expect(parameters.allSatisfy { $0.temperature == preset.temperature && $0.topK == preset.topK })
    }

    @Test func everyStageWritesInTheChosenLanguageWhateverTheTranscripts() async throws {
        let russianSpeech = SummaryFixtures.transcript(of: UUID(), lines: 6, language: "ru")

        _ = try await summarize(russianSpeech, batchTokens: 8, language: .english)

        let instructions = generator.read(\.requests).map { $0[0].content }
        #expect(instructions.count > 6)
        #expect(instructions.allSatisfy { $0.contains("Write only in English") })
        #expect(!instructions.contains { $0.contains("Russian") })
    }

    @Test func notesTooLongForOneBatchAreCondensedFirst() async throws {
        let transcript = SummaryFixtures.transcript(of: UUID(), lines: 6)

        // One line per batch; each note ("## span" + "notes N") is four tokens, so two fit eight.
        let output = try await summarize(transcript, batchTokens: 8)

        let stages = generator.read(\.requests).map { $0[0].content.prefix(14) }
        #expect(output.parts.count == 6)
        #expect(stages.filter { $0.hasPrefix("You condense") }.count >= 2)
        #expect(stages.last?.hasPrefix("You write") == true)
    }

    @Test func aTranscriptWithoutSpeechIsRefused() async {
        let empty = SummaryFixtures.transcript(of: UUID(), lines: 0)

        await #expect(throws: SummaryFailure.emptyTranscript) {
            _ = try await summarize(empty, batchTokens: 100)
        }
    }

    @Test func generatorFailuresBecomeSummaryFailures() async {
        generator.update { $0.failure = URLError(.badServerResponse) }

        await #expect {
            _ = try await summarize(SummaryFixtures.transcript(of: UUID(), lines: 1), batchTokens: 100)
        } throws: { error in
            guard case SummaryFailure.generationFailed = error else {
                return false
            }
            return true
        }
    }

    @Test func anEmptyReplyIsAFailure() async {
        let silent = SilentGenerator()
        let summarizer = TranscriptSummarizer(
            generator: silent,
            settings: SummaryFixtures.settings(batchTokens: 100),
            language: SummaryLanguage.english
        )

        await #expect(throws: SummaryFailure.generationFailed(detail: "The model returned no text")) {
            _ = try await summarizer.summarize(SummaryFixtures.transcript(of: UUID(), lines: 1)) { _ in }
        }
    }
}

/// Collects progress reports from the summarizer's callback.
private final class ProgressLog: Sendable {
    let updates = Mutex<[TranscriptSummarizer.Progress]>([])
}

private struct SilentGenerator: TextGenerator {
    func tokenCount(of text: String) async throws -> Int { 1 }

    func generate(_ messages: [TextGenerationMessage], parameters: TextGenerationParameters) async throws -> String {
        "<think>only thinking</think>"
    }
}
