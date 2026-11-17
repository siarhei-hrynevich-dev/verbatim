import Foundation

/// How a summary is written with a language model: how much transcript goes into each batch, how long the notes and
/// the summary may be, and how words are sampled. Each model has a preset; the user may adjust a copy of it.
struct SummarySettings: Codable, Equatable, Sendable {
    /// Transcript tokens per batch. Smaller batches keep memory down and detail up; larger ones need fewer passes.
    var batchTokens: Int
    /// The most tokens the notes on one batch may take.
    var batchNoteTokens: Int
    /// The most tokens the final summary may take.
    var summaryTokens: Int
    /// Randomness of word choice. Low values stay closest to the transcript.
    var temperature: Double
    /// Only words within this share of probability are considered.
    var topP: Double
    /// Only this many of the likeliest words are considered; 0 turns the limit off.
    var topK: Int
    /// Discourages repeating recent words; 1 turns it off.
    var repetitionPenalty: Double

    static let batchTokenRange = 1_000...16_000
    static let batchNoteTokenRange = 100...1_500
    static let summaryTokenRange = 100...2_000
    static let temperatureRange = 0.0...1.5
    static let topPRange = 0.05...1.0
    static let topKRange = 0...100
    static let repetitionPenaltyRange = 1.0...2.0

    /// Room left in the context for instructions and the prompt's own framing.
    static let promptOverheadTokens = 1_000

    /// Every value within its range, and a batch plus its notes within the model's context. Stored values may come
    /// from an older version, so they are clamped whenever they are used.
    func clamped(toContext contextTokens: Int) -> SummarySettings {
        var result = self
        result.batchNoteTokens = Self.clamp(batchNoteTokens, to: Self.batchNoteTokenRange)
        result.summaryTokens = Self.clamp(summaryTokens, to: Self.summaryTokenRange)
        let contextLimit = contextTokens - result.batchNoteTokens - Self.promptOverheadTokens
        let upper = max(Self.batchTokenRange.lowerBound, min(Self.batchTokenRange.upperBound, contextLimit))
        result.batchTokens = Self.clamp(batchTokens, to: Self.batchTokenRange.lowerBound...upper)
        result.temperature = Self.clamp(temperature, to: Self.temperatureRange)
        result.topP = Self.clamp(topP, to: Self.topPRange)
        result.topK = Self.clamp(topK, to: Self.topKRange)
        result.repetitionPenalty = Self.clamp(repetitionPenalty, to: Self.repetitionPenaltyRange)
        return result
    }

    private static func clamp<Value: Comparable>(_ value: Value, to range: ClosedRange<Value>) -> Value {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// A non-number from a damaged store falls to the lower bound rather than through every comparison.
    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else {
            return range.lowerBound
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
