import Foundation

/// What WhisperKit's detection reports for one chunk: only the language it picked, with that pick's log-probability
/// among languages, not a distribution over them.
struct LanguageDetection: Equatable, Sendable {
    let language: String
    let logProbability: Float
    let seconds: TimeInterval

    var probability: Double {
        exp(Double(logProbability))
    }
}

/// Which language automatic detection decodes speech in. A track gets one language from its first stretches of
/// speech, which each chunk keeps unless it is clearly in another: people in one meeting can switch languages, and a
/// chunk decoded in the wrong language comes out translated into it.
enum LanguageChoice {
    /// Each chunk votes for its language with its probability, weighted by its length. Log-probabilities are never
    /// added up: they are negative, so a language picked by fewer chunks would score higher. Weighting by length keeps
    /// a short reply full of English terms in Russian speech from counting as much as a long stretch of speech.
    static func trackLanguage(of detections: [LanguageDetection]) -> String? {
        var votes: [String: Double] = [:]
        for detection in detections {
            votes[detection.language, default: 0] += detection.probability * max(detection.seconds, 0)
        }
        return votes.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    /// The track's language, unless the chunk is long enough to judge and detected confidently as another. Short
    /// replies and speech sprinkled with another language's terms are easily detected as that language, and decoding
    /// them in it would translate them; a confident detection over several seconds is a real switch.
    static func chunkLanguage(_ detection: LanguageDetection?, trackLanguage: String) -> String {
        guard
            let detection,
            detection.seconds >= Tuning.minimumSwitchSeconds,
            detection.probability >= Tuning.minimumSwitchProbability
        else {
            return trackLanguage
        }
        return detection.language
    }

    private enum Tuning {
        static let minimumSwitchSeconds: TimeInterval = 4
        static let minimumSwitchProbability = 0.8
    }
}
