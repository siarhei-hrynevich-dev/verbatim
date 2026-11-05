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
