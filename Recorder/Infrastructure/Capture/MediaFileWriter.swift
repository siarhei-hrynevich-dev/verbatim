import AVFoundation
import CoreMedia

/// Writes video and separately stored audio tracks to one media file.
///
/// Not thread-safe: `CaptureSampleSink` confines it to its serial queue, where capture delivers every sample.
/// The file holds fragments as it grows, so an interrupted recording remains recoverable.
final class MediaFileWriter {
    struct VideoTrack {
        let size: PixelSize
        let frameRate: FrameRate
    }

    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput?
    private let audioInputs: [AudioSourceKind: AVAssetWriterInput]

    private var timeline = PauseTimeline()
    private var sessionStart: CMTime?
    private var sessionEnd = CMTime.invalid
    private var lastVideoFrame: CMSampleBuffer?
    private var lastAudioTimes: [AudioSourceKind: CMTime] = [:]

    /// Starts writing immediately, so an unusable output location fails before capture begins.
    init(url: URL, video: VideoTrack?, audioSources: [AudioSourceKind]) throws {
        assetWriter = try AVAssetWriter(outputURL: url, fileType: .mov)
        assetWriter.movieFragmentInterval = CMTime(value: Self.fragmentIntervalSeconds, timescale: 1)

        videoInput = video.map(Self.makeVideoInput)
        var inputs: [AudioSourceKind: AVAssetWriterInput] = [:]
        for source in audioSources {
            inputs[source] = Self.makeAudioInput(for: source)
        }
        audioInputs = inputs

        for input in [videoInput].compactMap(\.self) + audioSources.compactMap({ inputs[$0] }) {
            guard assetWriter.canAdd(input) else {
                throw WriterError.cannotAddTrack
            }
            assetWriter.add(input)
        }
        guard assetWriter.startWriting() else {
            throw assetWriter.error ?? WriterError.cannotStart
        }
    }

    /// The writer's error once it has failed. It accepts no more samples from then on.
    var failure: (any Error)? {
        assetWriter.status == .failed ? assetWriter.error ?? WriterError.cannotStart : nil
    }

    func pause(at time: CMTime) {
        timeline.pause(at: time)
    }

    func resume(at time: CMTime) {
        timeline.resume(at: time)
    }

    // MARK: - Samples

    /// The session opens on the first frame, so recordings with video never begin with a blank picture.
    /// A frame the encoder is not ready for is dropped; real-time capture must not fall behind.
    func appendVideoFrame(_ frame: CMSampleBuffer) {
        guard assetWriter.status == .writing, let videoInput,
            let outputTime = timeline.outputTime(for: frame.presentationTimeStamp)
        else {
            return
        }
        startSessionIfNeeded(at: outputTime)
        guard videoInput.isReadyForMoreMediaData, let retimed = Self.retimed(frame, startingAt: outputTime) else {
            return
        }
        if videoInput.append(retimed) {
            lastVideoFrame = retimed
            extendSession(to: outputTime)
        }
    }

    func appendAudio(_ sample: CMSampleBuffer, from source: AudioSourceKind) {
        guard assetWriter.status == .writing, let input = audioInputs[source],
            let outputTime = timeline.outputTime(for: sample.presentationTimeStamp)
        else {
            return
        }
        if videoInput == nil {
            startSessionIfNeeded(at: outputTime)
        }
        // Each track must only move forward, and audio from before the first frame has no place in the session.
        guard let sessionStart, outputTime >= sessionStart else {
            return
        }
        if let lastTime = lastAudioTimes[source], outputTime <= lastTime {
            return
        }
        guard input.isReadyForMoreMediaData, let retimed = Self.retimed(sample, startingAt: outputTime) else {
            return
        }
        if input.append(retimed) {
            lastAudioTimes[source] = outputTime
            extendSession(to: outputTime + retimed.duration)
        }
    }

    // MARK: - Finishing

    /// Closes the file. `stopTime` is the capture time of the stop request, which keeps the full length of a
    /// recording whose picture stopped changing. Discards the file if nothing was written.
    func finish(
        stopTime: CMTime,
        isolation: isolated (any Actor)? = #isolation
    ) async throws {
        guard assetWriter.status == .writing, sessionStart != nil else {
            if let failure {
                throw failure
            }
            assetWriter.cancelWriting()
            throw RecordingFailure.noMediaCaptured
        }
        if let endTime = timeline.endTime(forStopAt: stopTime) {
            extendSession(to: endTime)
        }
        holdLastVideoFrameUntilSessionEnd()
        videoInput?.markAsFinished()
        audioInputs.values.forEach { $0.markAsFinished() }
        assetWriter.endSession(atSourceTime: sessionEnd)
        let writer = assetWriter
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }
        guard assetWriter.status == .completed else {
            throw assetWriter.error ?? WriterError.cannotFinish
        }
    }

    /// Screen capture delivers frames only when the picture changes, so the last one must span the remaining time.
    private func holdLastVideoFrameUntilSessionEnd() {
        guard let videoInput, let lastVideoFrame, videoInput.isReadyForMoreMediaData,
            sessionEnd > lastVideoFrame.presentationTimeStamp,
            let finalFrame = Self.retimed(lastVideoFrame, startingAt: sessionEnd)
        else {
            return
        }
        videoInput.append(finalFrame)
    }

    private func startSessionIfNeeded(at time: CMTime) {
        guard sessionStart == nil else {
            return
        }
        assetWriter.startSession(atSourceTime: time)
        sessionStart = time
        sessionEnd = time
    }

    private func extendSession(to time: CMTime) {
        if !sessionEnd.isValid || time > sessionEnd {
            sessionEnd = time
        }
    }

    // MARK: - Configuration

    private static func makeVideoInput(for track: VideoTrack) -> AVAssetWriterInput {
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: track.size.width,
            AVVideoHeightKey: track.size.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: VideoEncodingProfile.averageBitRate(
                    for: track.size,
                    frameRate: track.frameRate
                ),
                AVVideoExpectedSourceFrameRateKey: track.frameRate.rawValue,
                AVVideoAllowFrameReorderingKey: false
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }

    /// The microphone arrives as mono from `MicrophoneCapture`; system audio as stereo from ScreenCaptureKit.
    private static func makeAudioInput(for source: AudioSourceKind) -> AVAssetWriterInput {
        let channelCount = source == .microphone ? 1 : 2
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: CaptureAudioFormat.sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: channelCount == 1 ? 96_000 : 160_000
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        input.metadata = [trackNameItem(for: source)]
        return input
    }

    /// Names the track so each audio source stays identifiable after recording.
    private static func trackNameItem(for source: AudioSourceKind) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .quickTimeUserDataTrackName
        item.value = CaptureAudioFormat.trackName(for: source) as NSString
        return item
    }

    private static func retimed(_ sample: CMSampleBuffer, startingAt outputTime: CMTime) -> CMSampleBuffer? {
        let offset = outputTime - sample.presentationTimeStamp
        guard offset != .zero else {
            return sample
        }
        guard let timings = try? sample.sampleTimingInfos() else {
            return nil
        }
        let shifted = timings.map { timing in
            CMSampleTimingInfo(
                duration: timing.duration,
                presentationTimeStamp: timing.presentationTimeStamp + offset,
                decodeTimeStamp: timing.decodeTimeStamp.isValid ? timing.decodeTimeStamp + offset : .invalid
            )
        }
        return try? CMSampleBuffer(copying: sample, withNewTiming: shifted)
    }

    /// Long enough to keep fragmentation cheap, short enough to limit what a crash can lose.
    private static let fragmentIntervalSeconds: CMTimeValue = 5

    private enum WriterError: Error {
        case cannotAddTrack
        case cannotStart
        case cannotFinish
    }
}

/// The audio format capture produces.
enum CaptureAudioFormat {
    static let sampleRate = 48_000

    static func trackName(for source: AudioSourceKind) -> String {
        switch source {
        case .microphone: "Microphone"
        case .systemAudio: "System Audio"
        }
    }
}
