import AVFoundation
import Foundation
import Testing

@testable import Recorder

/// Converts a speech file into a recording with the Recorder's track layout.
enum SpeechRecordingFixture {
    static func write(
        speech: URL,
        tracks: [(source: AudioSourceKind, start: TimeInterval)],
        roomToneSeconds: TimeInterval,
        repeats: Int,
        to url: URL
    ) async throws {
        let file = try AVAudioFile(forReading: speech)
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: true)
        )
        // Quiet noise, well above digital silence, as an open microphone in a quiet room gives.
        let roomTone = (0..<Int(roomToneSeconds * 48_000)).map { _ in Float.random(in: -0.002...0.002) }
        let speech = try resampled(file, to: format)
        var samples: [Float] = []
        samples.reserveCapacity((speech.count + roomTone.count) * repeats)
        for _ in 0..<repeats {
            samples += roomTone
            samples += speech
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        var inputs: [AVAssetWriterInput] = []
        for track in tracks {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 96_000
                ]
            )
            let item = AVMutableMetadataItem()
            item.identifier = .quickTimeUserDataTrackName
            item.value = CaptureAudioFormat.trackName(for: track.source) as NSString
            input.metadata = [item]
            writer.add(input)
            inputs.append(input)
        }
        guard writer.startWriting() else {
            throw writer.error ?? TestError.failed
        }
        writer.startSession(atSourceTime: .zero)
        try await append(samples, format: format, to: Array(zip(inputs, tracks.map(\.start))))
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? TestError.failed
        }
    }

    private static func resampled(_ file: AVAudioFile, to format: AVAudioFormat) throws -> [Float] {
        let source = try #require(
            AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        )
        try file.read(into: source)
        let converter = try #require(AVAudioConverter(from: file.processingFormat, to: format))
        let ratio = format.sampleRate / file.processingFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 4_096
        let output = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity))
        nonisolated(unsafe) var isDone = false
        nonisolated(unsafe) let input = source
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if isDone {
                status.pointee = .endOfStream
                return nil
            }
            isDone = true
            status.pointee = .haveData
            return input
        }
        if let conversionError {
            throw conversionError
        }
        let channel = try #require(output.floatChannelData)
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
    }

    /// Offers each track a buffer whenever it is ready: a writer that isn't real time holds a track back until the
    /// others have caught up with it, so filling them one after another would wait forever.
    private static func append(
        _ samples: [Float],
        format: AVAudioFormat,
        to tracks: [(input: AVAssetWriterInput, start: TimeInterval)]
    ) async throws {
        let bufferFrames = 4_800
        var offsets = [Int](repeating: 0, count: tracks.count)
        while offsets.contains(where: { $0 < samples.count }) {
            var didAppend = false
            for (index, track) in tracks.enumerated() where offsets[index] < samples.count {
                guard track.input.isReadyForMoreMediaData else {
                    continue
                }
                let offset = offsets[index]
                let count = min(bufferFrames, samples.count - offset)
                let time = CMTime(seconds: track.start + Double(offset) / 48_000, preferredTimescale: 48_000)
                let buffer = try pcmBuffer(samples[offset..<(offset + count)], format: format)
                guard track.input.append(try sampleBuffer(from: buffer, format: format, at: time)) else {
                    throw TestError.failed
                }
                offsets[index] += count
                didAppend = true
                if offsets[index] >= samples.count {
                    track.input.markAsFinished()
                }
            }
            if !didAppend {
                try await Task.sleep(for: .milliseconds(1))
            }
        }
    }

    private static func pcmBuffer(_ samples: ArraySlice<Float>, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channel = try #require(buffer.floatChannelData)
        for (index, sample) in samples.enumerated() {
            channel[0][index] = sample
        }
        return buffer
    }

    private static func sampleBuffer(
        from buffer: AVAudioPCMBuffer,
        format: AVAudioFormat,
        at time: CMTime
    ) throws -> CMSampleBuffer {
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 48_000),
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        var description: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil,
            asbd: format.streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &description
        )
        CMSampleBufferCreate(
            allocator: nil,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: description,
            sampleCount: CMItemCount(buffer.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sample
        )
        let created = try #require(sample)
        CMSampleBufferSetDataBufferFromAudioBufferList(
            created,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            bufferList: buffer.audioBufferList
        )
        return created
    }
}
