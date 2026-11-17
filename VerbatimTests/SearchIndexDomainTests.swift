import Foundation
import Testing

@testable import Verbatim

struct SearchIndexDomainTests {
    private let recordingID = UUID()

    @Test func shortSpeechIsOneChunkCoveringItsTimeAndSegments() throws {
        let transcript = SearchFixtures.transcript(of: recordingID, lines: SearchFixtures.planning)

        let chunks = SearchChunker.chunks(of: transcript)

        let chunk = try #require(chunks.first)
        #expect(chunks.count == 1)
        #expect(chunk.kind == .transcript)
        #expect(chunk.segments == 0...3)
        #expect(chunk.timeSpan == 0...79)
        #expect(chunk.text == SearchFixtures.planning.joined(separator: "\n"))
    }

    @Test func longSpeechIsSplitByDurationWithOneSegmentOfOverlap() {
        let lines = (0..<12).map { "Фраза номер \($0) о планах команды." }
        let transcript = SearchFixtures.transcript(of: recordingID, lines: lines, secondsPerLine: 20)

        let chunks = SearchChunker.chunks(of: transcript)

        #expect(chunks.map(\.position) == Array(0..<chunks.count))
        #expect(
            chunks.allSatisfy { chunk in
                guard let span = chunk.timeSpan else {
                    return false
                }
                return span.upperBound - span.lowerBound <= SearchChunker.maxDuration
            }
        )
        for (previous, next) in zip(chunks, chunks.dropFirst()) {
            #expect(next.segments?.lowerBound == previous.segments?.upperBound)
        }
        #expect(chunks.last?.segments?.upperBound == 11)
    }

    @Test func aSegmentOverTheLimitGetsAChunkOfItsOwnWithoutRepeats() {
        let long = String(repeating: "очень длинная фраза ", count: 80)
        let transcript = SearchFixtures.transcript(of: recordingID, lines: ["Начало.", long, "Конец."])

        let chunks = SearchChunker.chunks(of: transcript)

        #expect(chunks.map(\.segments) == [0...0, 1...1, 2...2])
    }

    @Test func aSummaryIsSplitIntoItsOverviewAndItsTimedParts() {
        let transcript = SearchFixtures.transcript(of: recordingID, lines: SearchFixtures.planning)
        let summary = SearchFixtures.summary(
            of: transcript,
            text: "Релиз переносится.\n\n- Сборка в среду",
            parts: ["- Планёрка по релизу", "- Ошибка микрофона"]
        )

        let chunks = SearchChunker.chunks(of: summary)

        #expect(chunks.filter { $0.kind == .summary }.map(\.text) == ["Релиз переносится.\n- Сборка в среду"])
        let parts = chunks.filter { $0.kind == .summaryPart }
        #expect(parts.map(\.position) == [0, 1])
        #expect(parts.map(\.timeSpan) == [0...59, 60...119])
        #expect(chunks.first { $0.kind == .summary }?.timeSpan == nil)
    }

    @Test func fusionRanksAgreementAboveEitherListAlone() {
        let semantic = [ScoredChunk(chunkID: 1, score: 0.9), ScoredChunk(chunkID: 2, score: 0.8)]
        let lexical = [ScoredChunk(chunkID: 3, score: -5), ScoredChunk(chunkID: 2, score: -4)]

        let fused = SearchRanking.fused([.semantic: semantic, .lexical: lexical])

        #expect(fused.map(\.chunkID) == [2, 1, 3])
        #expect(fused.first?.matches == [.semantic, .lexical])
        #expect(fused.last?.matches == [.lexical])
    }

    @Test(arguments: [
        ("релиз в среду", "\"релиз\"* OR \"в\"* OR \"среду\"*"),
        ("Deploy \"NOW\" OR (x)", "\"deploy\"* OR \"now\"* OR \"or\"* OR \"x\"*"),
        ("  ...  ", nil)
    ])
    func queriesBecomeSafeFullTextExpressions(query: String, expression: String?) {
        #expect(SQLiteSearchIndexRepository.fullTextExpression(for: query) == expression)
    }

    @Test func vectorsSurviveTheirStoredForm() throws {
        let vector: [Float] = [0.25, -1, 3.5e-8, .pi]

        let restored = try #require(VectorMatrix.vector(from: VectorMatrix.blob(from: vector)))

        #expect(restored == vector)
        #expect(VectorMatrix.blob(from: vector).count == 16)
        #expect(VectorMatrix.vector(from: Data([1, 2, 3])) == nil)
    }

    @Test func theMatrixReturnsTheClosestAllowedRowsFirst() {
        var matrix = VectorMatrix(dimensions: 2)
        matrix.append(chunkID: 10, vector: [1, 0])
        matrix.append(chunkID: 11, vector: [0.6, 0.8])
        matrix.append(chunkID: 12, vector: [0, 1])
        matrix.append(chunkID: 13, vector: [1, 0, 0])

        let nearest = matrix.nearest(to: [0.8, 0.6], limit: 2) { $0 != 11 }

        #expect(matrix.count == 3)
        #expect(nearest.map(\.chunkID) == [10, 12])
        #expect(abs((nearest.first?.score ?? 0) - 0.8) < 0.0001)
    }
}
