import AVFoundation
import Foundation
import OSLog
import ScreenCaptureKit

/// What to capture. ScreenCaptureKit's objects are not Sendable, so a plan is handed over whole.
struct CapturePlan {
    struct Video {
        let filter: SCContentFilter
        let size: PixelSize
        let frameRate: FrameRate
    }

    var microphone: Microphone?
    var systemAudioDisplay: SCDisplay?
    var video: Video?
}

/// One running capture: an optional video stream, an optional system audio stream and an optional microphone, all
/// delivering to the same sink. Audio has its own stream so that every capture mode records all applications' audio.
actor LiveCaptureSession: CaptureSession {
    nonisolated let events: AsyncStream<CaptureEvent>

    private let continuation: AsyncStream<CaptureEvent>.Continuation
    private let sink: CaptureSampleSink
    private let outputURL: URL?
    private var videoStream: RunningStream?
    private var audioStream: RunningStream?
    private var microphone: MicrophoneCapture?
    private var sourceMonitor: Task<Void, Never>?
    private var isStopped = false

    private struct RunningStream {
        let stream: SCStream
        let output: StreamOutput
    }

    /// Without `writer`, the session only reports levels.
    init(writer: consuming sending MediaFileWriter?, outputURL: URL?) {
        let (events, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        self.events = events
        self.continuation = continuation
        self.outputURL = outputURL
        sink = CaptureSampleSink(writer: writer, events: continuation)
    }

    // MARK: - Starting

    /// Audio starts first, so a recording's first frame already has audio running.
    func start(_ plan: sending CapturePlan) async throws {
        if let microphone = plan.microphone {
            let capture = MicrophoneCapture(events: continuation)
            try await capture.start(microphone, sink: sink)
            self.microphone = capture
        }
        if let display = plan.systemAudioDisplay {
            try await startSystemAudio(display: display)
        }
        if let video = plan.video {
            try await startVideo(video)
        }
    }

    private func startSystemAudio(display: SCDisplay) async throws {
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = CaptureAudioFormat.sampleRate
        configuration.channelCount = 2
        // ScreenCaptureKit has no audio-only stream, so the picture is made as small and rare as allowed.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let continuation = continuation
        let output = StreamOutput(sink: sink, role: .systemAudio) { error in
            continuation.yield(.systemAudioLost(detail: error.localizedDescription))
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: sink.sampleQueue)
        // Without a screen output the stream logs an error for every discarded frame.
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sink.sampleQueue)
        try await start(stream)
        audioStream = RunningStream(stream: stream, output: output)
    }

    private func startVideo(_ video: CapturePlan.Video) async throws {
        let configuration = SCStreamConfiguration()
        configuration.width = video.size.width
        configuration.height = video.size.height
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(video.frameRate.rawValue))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.queueDepth = 8
        configuration.showsCursor = true

        let continuation = continuation
        let output = StreamOutput(sink: sink, role: .video) { error in
            Self.logger.error("Video stream stopped: \(String(describing: error))")
            continuation.yield(.videoSourceLost)
        }
        let stream = SCStream(filter: video.filter, configuration: configuration, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sink.sampleQueue)
        try await start(stream)
        videoStream = RunningStream(stream: stream, output: output)
    }

    /// A closed window does not reliably end its stream, so the source is also checked periodically.
    func monitorVideoSource(isAvailable: @escaping @Sendable () async -> Bool) {
        let continuation = continuation
        sourceMonitor = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.sourceCheckInterval)
                } catch {
                    return
                }
                guard await isAvailable() else {
                    continuation.yield(.videoSourceLost)
                    return
                }
            }
        }
    }

    // MARK: - CaptureSession

    func pause() async {
        await sink.pause()
    }

    func resume() async {
        await sink.resume()
    }

    func stopCapture() async {
        guard !isStopped else {
            return
        }
        isStopped = true
        sourceMonitor?.cancel()
        sourceMonitor = nil
        await microphone?.stop()
        for running in [videoStream, audioStream].compactMap(\.self) {
            await stop(running.stream)
        }
        continuation.finish()
    }

    func finalize() async throws -> CapturedMedia {
        try await sink.finishWriting()
        guard let outputURL else {
            throw RecordingFailure.noMediaCaptured
        }
        return try await MediaValidator.validate(outputURL)
    }

    // MARK: - Streams

    private func start(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// A stream that already ended by itself reports an error here; there is nothing left to stop.
    private func stop(_ stream: SCStream) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stream.stopCapture { error in
                if let error {
                    Self.logger.info("Stream was already stopped: \(String(describing: error))")
                }
                continuation.resume()
            }
        }
    }

    private static let sourceCheckInterval = Duration.seconds(2)
    private static let logger = Logger(subsystem: "dev.local.Recorder", category: "Capture")
}

/// Forwards ScreenCaptureKit callbacks to the sink. Runs on the sink's queue, as `addStreamOutput` was told.
private final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, Sendable {
    enum Role {
        case video
        case systemAudio
    }

    private let sink: CaptureSampleSink
    private let role: Role
    private let onStop: @Sendable (any Error) -> Void

    init(sink: CaptureSampleSink, role: Role, onStop: @escaping @Sendable (any Error) -> Void) {
        self.sink = sink
        self.role = role
        self.onStop = onStop
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else {
            return
        }
        switch (role, type) {
        case (.video, .screen):
            if Self.hasNewPicture(sampleBuffer) {
                sink.deliverVideoFrame(sampleBuffer)
            }
        case (.systemAudio, .audio):
            sink.deliverAudio(sampleBuffer, from: .systemAudio)
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onStop(error)
    }

    /// Screen capture also delivers buffers that only say nothing changed, and those hold no image.
    private static func hasNewPicture(_ sample: CMSampleBuffer) -> Bool {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: rawStatus)
        else {
            return false
        }
        return status == .complete && sample.imageBuffer != nil
    }
}

/// Confirms that a finished file is real playable media before the recording is reported as saved.
enum MediaValidator {
    static func validate(_ url: URL) async throws -> CapturedMedia {
        let asset = AVURLAsset(url: url)
        let (isPlayable, duration, tracks) = try await asset.load(.isPlayable, .duration, .tracks)
        guard isPlayable, duration.isValid, duration.seconds > 0 else {
            throw ValidationError.notPlayable
        }
        let sizeBytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard sizeBytes > 0 else {
            throw ValidationError.notPlayable
        }
        var audioSources: [AudioSourceKind] = []
        for track in tracks where track.mediaType == .audio {
            let metadata = try await track.load(.metadata)
            let names = AVMetadataItem.metadataItems(
                from: metadata,
                filteredByIdentifier: .quickTimeUserDataTrackName
            )
            let name = try await names.first?.load(.stringValue)
            let source: AudioSourceKind =
                name == CaptureAudioFormat.trackName(for: .microphone) ? .microphone : .systemAudio
            audioSources.append(source)
        }
        return CapturedMedia(
            duration: duration.seconds,
            fileSizeBytes: Int64(sizeBytes),
            hasVideo: tracks.contains { $0.mediaType == .video },
            audioSources: audioSources
        )
    }

    enum ValidationError: LocalizedError {
        case notPlayable

        var errorDescription: String? {
            String(localized: "The finished file is not playable media.")
        }
    }
}
