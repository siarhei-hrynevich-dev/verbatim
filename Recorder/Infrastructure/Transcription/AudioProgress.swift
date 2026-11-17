import Foundation

/// Measures progress as audio finished out of all audio to transcribe, across sources. Whisper's windows make it step
/// roughly every 30 seconds of audio.
struct AudioProgress {
    private let totalSeconds: TimeInterval
    private let onUpdate: @Sendable (TranscriptionUpdate) -> Void
    private var finishedSeconds: TimeInterval = 0

    init(layout: RecordingAudioLayout, onUpdate: @escaping @Sendable (TranscriptionUpdate) -> Void) {
        totalSeconds = layout.inputs.reduce(0) { $0 + max($1.durationSeconds, 0) }
        self.onUpdate = onUpdate
    }

    func advance(_ input: RecordingAudioInput, toSample sample: Int) {
        let seconds = TimeInterval(sample) / TimeInterval(AudioTimelineAssembler.sampleRate)
        report(finishedSeconds + min(seconds, input.durationSeconds))
    }

    mutating func finish(_ input: RecordingAudioInput) {
        finishedSeconds += max(input.durationSeconds, 0)
        report(finishedSeconds)
    }

    private func report(_ seconds: TimeInterval) {
        guard totalSeconds > 0 else {
            return
        }
        onUpdate(.processingAudio(fraction: min(seconds / totalSeconds, 1)))
    }
}
