import Accelerate
import CoreMedia
import QuartzCore

/// Receives every captured sample on one serial queue, measures audio levels and passes samples to the writer.
///
/// The actor runs on the queue that capture delivers samples on, so delivery can enter its isolation synchronously
/// instead of hopping through a task per sample, which would risk reordering them. A sink without a writer only
/// measures levels.
actor CaptureSampleSink {
    private let queue: DispatchSerialQueue
    private let events: AsyncStream<CaptureEvent>.Continuation
    private var writer: MediaFileWriter?
    private var pendingLevels = AudioLevels.silent
    private var lastPublishTime = 0.0
    private var hasReportedWriteFailure = false

    init(writer: consuming sending MediaFileWriter?, events: AsyncStream<CaptureEvent>.Continuation) {
        queue = DispatchSerialQueue(label: "dev.local.Recorder.capture-samples", qos: .userInteractive)
        self.writer = writer
        self.events = events
    }

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// The queue to give capture APIs as their sample handler queue.
    nonisolated var sampleQueue: DispatchQueue {
        queue
    }

    /// Must be called on `sampleQueue`.
    nonisolated func deliverVideoFrame(_ frame: CMSampleBuffer) {
        // The buffer stays on this queue, which is the actor's own executor, so nothing crosses an isolation boundary.
        nonisolated(unsafe) let frame = frame
        assumeIsolated { sink in
            sink.writer?.appendVideoFrame(frame)
            sink.reportWriterFailure()
        }
    }

    /// Must be called on `sampleQueue`.
    nonisolated func deliverAudio(_ sample: CMSampleBuffer, from source: AudioSourceKind) {
        // The buffer stays on this queue, which is the actor's own executor, so nothing crosses an isolation boundary.
        nonisolated(unsafe) let sample = sample
        assumeIsolated { sink in
            sink.measure(sample, from: source)
            sink.writer?.appendAudio(sample, from: source)
            sink.reportWriterFailure()
        }
    }

    func pause() {
        writer?.pause(at: Self.hostTimeNow)
    }

    func resume() {
        writer?.resume(at: Self.hostTimeNow)
    }

    func finishWriting() async throws {
        guard let writer else {
            return
        }
        self.writer = nil
        try await writer.finish(stopTime: Self.hostTimeNow)
    }

    private func reportWriterFailure() {
        guard !hasReportedWriteFailure, let failure = writer?.failure else {
            return
        }
        hasReportedWriteFailure = true
        events.yield(.writeFailed(detail: failure.localizedDescription))
    }

    private func measure(_ sample: CMSampleBuffer, from source: AudioSourceKind) {
        let level = AudioLevels.normalized(rms: Self.rootMeanSquare(of: sample))
        switch source {
        case .microphone: pendingLevels.microphone = max(pendingLevels.microphone, level)
        case .systemAudio: pendingLevels.systemAudio = max(pendingLevels.systemAudio, level)
        }
        let time = CACurrentMediaTime()
        guard time - lastPublishTime >= Self.levelPublishIntervalSeconds else {
            return
        }
        lastPublishTime = time
        events.yield(.levels(pendingLevels))
        pendingLevels = .silent
    }

    /// Capture audio is 32-bit float: ScreenCaptureKit always delivers it, and `MicrophoneCapture` requests it.
    private static func rootMeanSquare(of sample: CMSampleBuffer) -> Double {
        var rootMeanSquare: Float = 0
        do {
            try sample.withAudioBufferList { buffers, _ in
                guard let buffer = buffers.first, let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                    return
                }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                vDSP_rmsqv(samples, 1, &rootMeanSquare, vDSP_Length(count))
            }
        } catch {
            return 0
        }
        return Double(rootMeanSquare)
    }

    private static var hostTimeNow: CMTime {
        CMClockGetTime(CMClockGetHostTimeClock())
    }

    private static let levelPublishIntervalSeconds = 0.1
}
