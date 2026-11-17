import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Testing

@testable import Verbatim

/// Exercises the real writer and validator with synthetic samples, which needs no capture hardware or permissions.
@MainActor
struct MediaFileWriterTests {
    private static let frameRate = 30

    private func withOutput(fileName: String, _ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MediaFileWriterTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory.appending(path: fileName))
    }

    private func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 48_000)
    }

    /// Feeds one second-range of frames and audio.
    private func feed(
        _ writer: MediaFileWriter,
        from start: Double,
        to end: Double,
        audioSources: [AudioSourceKind],
        video: Bool
    ) throws {
        let frameCount = Int((end - start) * Double(Self.frameRate))
        if video {
            for index in 0..<frameCount {
                let frame = try SyntheticSamples.videoFrame(at: time(start + Double(index) / Double(Self.frameRate)))
                writer.appendVideoFrame(frame)
            }
        }
        let audioBufferSeconds = 0.1
        for index in 0..<Int((end - start) / audioBufferSeconds) {
            let bufferStart = time(start + Double(index) * audioBufferSeconds)
            for source in audioSources {
                let channelCount = source == .microphone ? 1 : 2
                let sample = try SyntheticSamples.audio(
                    at: bufferStart,
                    channels: channelCount,
                    seconds: audioBufferSeconds
                )
                writer.appendAudio(sample, from: source)
            }
        }
    }

    @Test func writesAPlayableMovieWithSeparateNamedAudioTracks() async throws {
        try await withOutput(fileName: "recording.mov") { url in
            let writer = try MediaFileWriter(
                url: url,
                video: .init(size: PixelSize(width: 640, height: 360), frameRate: .fps30),
                audioSources: [.microphone, .systemAudio]
            )

            try feed(writer, from: 10, to: 12, audioSources: [.microphone, .systemAudio], video: true)
            try await writer.finish(stopTime: time(12))

            let media = try await MediaValidator.validate(url)
            #expect(media.hasVideo)
            #expect(Set(media.audioSources) == [.microphone, .systemAudio])
            #expect(media.audioSources.count == 2)
            #expect(abs(media.duration - 2) < 0.2)
            #expect(media.fileSizeBytes > 0)

            let asset = AVURLAsset(url: url)
            let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)
            let (size, formats) = try await videoTrack.load(.naturalSize, .formatDescriptions)
            #expect(size == CGSize(width: 640, height: 360))
            #expect(formats.first?.mediaSubType == .hevc)
        }
    }

    @Test func writesAPlayableAudioFileWithoutVideo() async throws {
        try await withOutput(fileName: "recording.mov") { url in
            let writer = try MediaFileWriter(url: url, video: nil, audioSources: [.microphone, .systemAudio])

            try feed(writer, from: 5, to: 7, audioSources: [.microphone, .systemAudio], video: false)
            try await writer.finish(stopTime: time(7))

            let media = try await MediaValidator.validate(url)
            #expect(!media.hasVideo)
            #expect(Set(media.audioSources) == [.microphone, .systemAudio])
            #expect(abs(media.duration - 2) < 0.2)
        }
    }

    @Test func aStaticPictureKeepsTheFullDuration() async throws {
        try await withOutput(fileName: "recording.mov") { url in
            let writer = try MediaFileWriter(
                url: url,
                video: .init(size: PixelSize(width: 640, height: 360), frameRate: .fps30),
                audioSources: []
            )

            writer.appendVideoFrame(try SyntheticSamples.videoFrame(at: time(10)))
            try await writer.finish(stopTime: time(14))

            let media = try await MediaValidator.validate(url)
            #expect(abs(media.duration - 4) < 0.1)
        }
    }

    @Test func pausedTimeLeavesNoGap() async throws {
        try await withOutput(fileName: "recording.mov") { url in
            let writer = try MediaFileWriter(url: url, video: nil, audioSources: [.microphone])

            try feed(writer, from: 0, to: 2, audioSources: [.microphone], video: false)
            writer.pause(at: time(2))
            // Captured during the pause, so it must be dropped.
            try feed(writer, from: 2, to: 5, audioSources: [.microphone], video: false)
            writer.resume(at: time(5))
            try feed(writer, from: 5, to: 7, audioSources: [.microphone], video: false)
            try await writer.finish(stopTime: time(7))

            let media = try await MediaValidator.validate(url)
            #expect(abs(media.duration - 4) < 0.2)
        }
    }

    @Test func audioBeforeTheFirstFrameIsNotPartOfTheMovie() async throws {
        try await withOutput(fileName: "recording.mov") { url in
            let writer = try MediaFileWriter(
                url: url,
                video: .init(size: PixelSize(width: 640, height: 360), frameRate: .fps30),
                audioSources: [.microphone]
            )

            writer.appendAudio(try SyntheticSamples.audio(at: time(9), channels: 1, seconds: 0.5), from: .microphone)
            try feed(writer, from: 10, to: 11, audioSources: [.microphone], video: true)
            try await writer.finish(stopTime: time(11))

            let media = try await MediaValidator.validate(url)
            #expect(abs(media.duration - 1) < 0.2)
        }
    }

    @Test func outOfOrderAudioDoesNotFailTheFile() async throws {
        try await withOutput(fileName: "recording.mov") { url in
            let writer = try MediaFileWriter(url: url, video: nil, audioSources: [.microphone])

            writer.appendAudio(try SyntheticSamples.audio(at: time(1), channels: 1, seconds: 0.1), from: .microphone)
            writer.appendAudio(try SyntheticSamples.audio(at: time(0.5), channels: 1, seconds: 0.1), from: .microphone)
            writer.appendAudio(try SyntheticSamples.audio(at: time(1.1), channels: 1, seconds: 0.1), from: .microphone)
            #expect(writer.failure == nil)

            try await writer.finish(stopTime: time(1.2))
            _ = try await MediaValidator.validate(url)
        }
    }

    @Test func nothingWrittenReportsNoMedia() async throws {
        try await withOutput(fileName: "recording.mov") { url in
            let writer = try MediaFileWriter(
                url: url,
                video: .init(size: PixelSize(width: 640, height: 360), frameRate: .fps30),
                audioSources: [.microphone]
            )

            await #expect(throws: RecordingFailure.noMediaCaptured) {
                try await writer.finish(stopTime: time(1))
            }
        }
    }

    @Test func aFileThatIsNotMediaFailsValidation() async throws {
        try await withOutput(fileName: "recording.mov") { url in
            try Data("not a movie".utf8).write(to: url)

            await #expect(throws: (any Error).self) {
                _ = try await MediaValidator.validate(url)
            }
        }
    }

    @Test func outputFileIsNeverOverwritten() async throws {
        try await withOutput(fileName: "recording.mov") { url in
            try Data("existing".utf8).write(to: url)

            #expect(throws: (any Error).self) {
                _ = try MediaFileWriter(url: url, video: nil, audioSources: [.microphone])
            }
            #expect(try Data(contentsOf: url) == Data("existing".utf8))
        }
    }
}

/// The delivery path capture uses: samples arrive on the sink's queue and enter its isolation synchronously.
struct CaptureSampleSinkTests {
    private func deliver(on sink: CaptureSampleSink, _ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            sink.sampleQueue.async {
                work()
                continuation.resume()
            }
        }
    }

    @Test func writesDeliveredSamplesAndReportsLevels() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "CaptureSampleSinkTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "recording.mov")
        let (events, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        let sink = CaptureSampleSink(
            writer: try MediaFileWriter(url: url, video: nil, audioSources: [.microphone]),
            events: continuation
        )
        let hostNow = CMClockGetTime(CMClockGetHostTimeClock())

        for index in 0..<10 {
            let start = hostNow + CMTime(seconds: Double(index) * 0.1, preferredTimescale: 48_000)
            nonisolated(unsafe) let sample = try SyntheticSamples.audio(at: start, channels: 1, seconds: 0.1)
            await deliver(on: sink) {
                sink.deliverAudio(sample, from: .microphone)
            }
        }
        try await sink.finishWriting()
        continuation.finish()

        var loudest = 0.0
        for await event in events {
            if case .levels(let levels) = event {
                loudest = max(loudest, levels.microphone)
            }
        }
        #expect(loudest > 0.5)
        let media = try await MediaValidator.validate(url)
        #expect(media.audioSources == [.microphone])
    }

    @Test func aSinkWithoutAWriterOnlyMeasures() async throws {
        let (events, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        let sink = CaptureSampleSink(writer: nil, events: continuation)
        nonisolated(unsafe) let sample = try SyntheticSamples.audio(at: .zero, channels: 2, seconds: 0.1)

        await deliver(on: sink) {
            sink.deliverAudio(sample, from: .systemAudio)
        }
        try await sink.finishWriting()
        continuation.finish()

        var systemAudioLevel = 0.0
        for await event in events {
            if case .levels(let levels) = event {
                systemAudioLevel = levels.systemAudio
            }
        }
        #expect(systemAudioLevel > 0.5)
    }

    /// AVFoundation raises an exception for settings it does not accept.
    @Test func microphoneOutputAcceptsTheRequestedFormat() {
        _ = MicrophoneCapture.makeDataOutput()
    }
}

struct PauseTimelineTests {
    private func time(_ seconds: Int64) -> CMTime {
        CMTime(value: seconds, timescale: 1)
    }

    @Test func mapsTimeAroundPauses() {
        var timeline = PauseTimeline()
        #expect(timeline.outputTime(for: time(5)) == time(5))

        timeline.pause(at: time(10))
        #expect(timeline.outputTime(for: time(9)) == time(9))
        #expect(timeline.outputTime(for: time(12)) == nil)

        timeline.resume(at: time(20))
        #expect(timeline.outputTime(for: time(15)) == nil)
        #expect(timeline.outputTime(for: time(25)) == time(15))

        timeline.pause(at: time(30))
        timeline.resume(at: time(35))
        #expect(timeline.outputTime(for: time(40)) == time(25))
    }

    @Test func stoppingWhilePausedEndsWhereThePauseBegan() throws {
        var timeline = PauseTimeline()
        timeline.pause(at: time(10))

        let end = try #require(timeline.endTime(forStopAt: time(100)))

        #expect(abs(end.seconds - 10) < 0.001)
    }
}

/// Generates sample buffers shaped like what capture delivers.
enum SyntheticSamples {
    enum SampleError: Error {
        case creationFailed
    }

    static func videoFrame(at time: CMTime) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 640, 360, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        guard let pixelBuffer else {
            throw SampleError.creationFailed
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(base, 0x80, CVPixelBufferGetDataSize(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        let format = try CMVideoFormatDescription(imageBuffer: pixelBuffer)
        let timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        return try CMSampleBuffer(imageBuffer: pixelBuffer, formatDescription: format, sampleTiming: timing)
    }

    static func audio(at time: CMTime, channels: Int, seconds: Double) throws -> CMSampleBuffer {
        let frameCount = AVAudioFrameCount(seconds * 48_000)
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: AVAudioChannelCount(channels),
                interleaved: channels == 1
            ),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let channelData = buffer.floatChannelData
        else {
            throw SampleError.creationFailed
        }
        buffer.frameLength = frameCount
        for channel in 0..<channels {
            for frame in 0..<Int(frameCount) {
                channelData[channel][frame] = sin(Float(frame) * 0.05) * 0.25
            }
        }
        return try sampleBuffer(from: buffer, format: format, frameCount: frameCount, at: time)
    }

    private static func sampleBuffer(
        from buffer: AVAudioPCMBuffer,
        format: AVAudioFormat,
        frameCount: AVAudioFrameCount,
        at time: CMTime
    ) throws -> CMSampleBuffer {
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 48_000),
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        CMSampleBufferCreate(
            allocator: nil,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format.formatDescription,
            sampleCount: CMItemCount(frameCount),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sample
        )
        guard let sample else {
            throw SampleError.creationFailed
        }
        let status = CMSampleBufferSetDataBufferFromAudioBufferList(
            sample,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            bufferList: buffer.audioBufferList
        )
        guard status == noErr else {
            throw SampleError.creationFailed
        }
        return sample
    }
}
