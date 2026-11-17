import Foundation
import Testing

@testable import Recorder

struct WhisperSegmentFilterTests {
    @Test(
        arguments: [
            (Float(0.9), Float(-1.5), true),
            (Float(0.9), Float(-0.3), false),
            (Float(0.1), Float(-1.5), false),
            (Float(0.1), Float(-0.3), false)
        ]
    )
    func dropsOnlySegmentsThatAreBothLikelySilenceAndLowConfidence(
        noSpeech: Float,
        logProbability: Float,
        isInvented: Bool
    ) {
        #expect(
            WhisperTranscriptionService.isLikelyInvented(
                noSpeechProbability: noSpeech,
                averageLogProbability: logProbability
            ) == isInvented
        )
    }
}

struct LanguageVoteTests {
    private typealias Detection = LanguageDetection

    @Test
    func theLanguageMostChunksPickWinsOverOneConfidentOutlier() {
        let detections = [
            Detection(language: "ru", logProbability: -0.3, seconds: 20),
            Detection(language: "ru", logProbability: -0.4, seconds: 20),
            Detection(language: "en", logProbability: -0.1, seconds: 20)
        ]
        #expect(LanguageChoice.trackLanguage(of: detections) == "ru")
    }

    @Test
    func aShortChunkCountsLessThanALongOne() {
        let detections = [
            Detection(language: "en", logProbability: -0.05, seconds: 3),
            Detection(language: "en", logProbability: -0.05, seconds: 4),
            Detection(language: "ru", logProbability: -0.5, seconds: 25)
        ]
        #expect(LanguageChoice.trackLanguage(of: detections) == "ru")
    }

    @Test
    func nothingDetectedDecidesNothing() {
        #expect(LanguageChoice.trackLanguage(of: []) == nil)
    }

    @Test
    func aLongConfidentChunkInAnotherLanguageSwitchesToIt() {
        let english = Detection(language: "en", logProbability: log(0.95), seconds: 20)
        #expect(LanguageChoice.chunkLanguage(english, trackLanguage: "es") == "en")
    }

    @Test(
        arguments: [
            (Float(log(0.95)), TimeInterval(2)),
            (Float(log(0.6)), TimeInterval(20))
        ]
    )
    func aShortOrUnsureChunkKeepsTheTrackLanguage(logProbability: Float, seconds: TimeInterval) {
        let english = Detection(language: "en", logProbability: logProbability, seconds: seconds)
        #expect(LanguageChoice.chunkLanguage(english, trackLanguage: "ru") == "ru")
    }

    @Test
    func aChunkWithoutDetectionKeepsTheTrackLanguage() {
        #expect(LanguageChoice.chunkLanguage(nil, trackLanguage: "es") == "es")
    }
}

struct SpeechChunkLevelTests {
    @Test
    func idleMicrophoneNoiseIsSilentButQuietSpeechIsNot() {
        let noise = (0..<16_000).map { Float(sin(Double($0) * 0.3)) * 0.000_3 }
        let quietSpeech = (0..<16_000).map { Float(sin(Double($0) * 0.3)) * 0.02 }
        #expect(SpeechChunk(startSample: 0, samples: noise).isSilent)
        #expect(!SpeechChunk(startSample: 0, samples: quietSpeech).isSilent)
    }

    @Test
    func aFewClicksOnAnIdleMicrophoneAreNotSpeech() {
        var samples = (0..<480_000).map { Float(sin(Double($0) * 0.3)) * 0.000_3 }
        for click in [100_000, 250_000, 400_000] {
            for index in click..<(click + 2_400) {
                samples[index] = 0.01
            }
        }
        #expect(SpeechChunk(startSample: 0, samples: samples).isSilent)
    }

    @Test
    func subtitleCreditsAreNotSpeech() {
        #expect(!WhisperTranscriptionService.isSpeech("Субтитры создавал DimaTorzok"))
        #expect(WhisperTranscriptionService.isSpeech("Субтитры нужны не всем."))
    }
}
