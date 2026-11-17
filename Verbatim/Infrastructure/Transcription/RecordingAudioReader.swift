@preconcurrency import AVFoundation
import CoreMedia
import os

/// One audio source of a recording, to be read and transcribed on its own.
struct RecordingAudioInput: Equatable, Sendable {
    let source: TranscriptSource
    /// A single track, or several mixed together when they cannot be told apart.
    let trackIDs: [CMPersistentTrackID]
    /// How much audio it holds, for measuring progress.
    let durationSeconds: TimeInterval
}

/// What a recording's file holds, as far as transcription is concerned.
struct RecordingAudioLayout: Equatable, Sendable {
    let inputs: [RecordingAudioInput]
    let mediaDuration: TimeInterval

    /// The Recorder names each track after its source, which is what keeps “You” and “System Audio” apart. Files
    /// without those names, as a located file from elsewhere can be, cannot be attributed: they are mixed and labeled
    /// Unknown, which also avoids transcribing the same speech twice when tracks are alternatives of one another.
    static func inspect(_ url: URL) async throws -> RecordingAudioLayout {
        let asset = AVURLAsset(url: url)
        let duration: CMTime
        let tracks: [AVAssetTrack]
        do {
            duration = try await asset.load(.duration)
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw TranscriptionFailure.unsupportedAudio(detail: error.localizedDescription)
        }
        guard !tracks.isEmpty else {
            throw TranscriptionFailure.noAudio
        }
        var named: [RecordingAudioInput] = []
        for track in tracks {
            guard let source = try await source(of: track) else {
                continue
            }
            let range = try await track.load(.timeRange)
            named.append(
                RecordingAudioInput(source: source, trackIDs: [track.trackID], durationSeconds: range.duration.seconds)
            )
        }
        let isAttributable = named.count == tracks.count && Set(named.map(\.source)).count == tracks.count
        let mixed = RecordingAudioInput(
            source: .unknown,
            trackIDs: tracks.map(\.trackID),
            durationSeconds: duration.seconds
        )
        return RecordingAudioLayout(inputs: isAttributable ? named : [mixed], mediaDuration: duration.seconds)
    }

    private static func source(of track: AVAssetTrack) async throws -> TranscriptSource? {
        let metadata = try await track.load(.metadata)
        let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .quickTimeUserDataTrackName)
        let name = try await items.first?.load(.stringValue)
        switch name {
        case CaptureAudioFormat.trackName(for: .microphone): return .microphone
        case CaptureAudioFormat.trackName(for: .systemAudio): return .systemAudio
        default: return nil
        }
    }
}

/// Decodes one audio input to what speech recognition takes, a block at a time: the file is never read whole, however
/// long it is, and nothing is written to disk.
///
/// Sample positions come from each decoded buffer's own presentation time, which is the timeline `AVPlayer` plays. A
/// track that starts late is stored with an empty edit, which decodes as silence from time 0, so its speech lands where
/// playback has it. Not thread-safe: it belongs to the task reading it.
final class RecordingAudioReader {
    private let reader: AVAssetReader
    private let output: AVAssetReaderOutput
    private var timeline = AudioTimelineAssembler()
    private var readyBlocks: [AudioBlock] = []
    private var isFinished = false

    /// Throws `TranscriptionFailure`.
    init(url: URL, input: RecordingAudioInput) async throws {
        let asset = AVURLAsset(url: url)
        do {
            reader = try AVAssetReader(asset: asset)
            let allTracks = try await asset.loadTracks(withMediaType: .audio)
            let tracks = allTracks.filter { input.trackIDs.contains($0.trackID) }
            output = Self.makeOutput(for: tracks)
        } catch {
            throw TranscriptionFailure.unsupportedAudio(detail: error.localizedDescription)
        }
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw TranscriptionFailure.unsupportedAudio(detail: "The audio tracks cannot be decoded.")
        }
        reader.add(output)
        guard reader.startReading() else {
            let detail = reader.error?.localizedDescription ?? "The audio tracks cannot be read."
            throw TranscriptionFailure.audioExtractionFailed(detail: detail)
        }
    }

    deinit {
        reader.cancelReading()
    }

    /// The next block of contiguous audio in timeline order, or `nil` at the end. Throws `TranscriptionFailure`.
    func nextBlock() throws -> AudioBlock? {
        while readyBlocks.isEmpty, !isFinished {
            try readNextBuffer()
        }
        return readyBlocks.isEmpty ? nil : readyBlocks.removeFirst()
    }

    private func readNextBuffer() throws {
        try autoreleasepool {
            guard let buffer = output.copyNextSampleBuffer() else {
                guard reader.status != .failed else {
                    let detail = reader.error?.localizedDescription ?? "Decoding stopped."
                    throw TranscriptionFailure.audioExtractionFailed(detail: detail)
                }
                isFinished = true
                readyBlocks += timeline.finish()
                return
            }
            guard let samples = Self.samples(in: buffer), buffer.presentationTimeStamp.isNumeric else {
                return
            }
            let position = Int(
                (buffer.presentationTimeStamp.seconds * Double(AudioTimelineAssembler.sampleRate)).rounded()
            )
            readyBlocks += timeline.append(samples, at: position)
        }
    }

    private static func makeOutput(for tracks: [AVAssetTrack]) -> AVAssetReaderOutput {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: AudioTimelineAssembler.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        if tracks.count == 1, let track = tracks.first {
            return AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        }
        return AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
    }

    private static func samples(in buffer: CMSampleBuffer) -> [Float]? {
        guard let block = buffer.dataBuffer else {
            return nil
        }
        let byteCount = CMBlockBufferGetDataLength(block)
        let count = byteCount / MemoryLayout<Float>.stride
        guard count > 0 else {
            return nil
        }
        return [Float](unsafeUninitializedCapacity: count) { samples, initializedCount in
            guard let destination = samples.baseAddress else {
                return
            }
            let status = CMBlockBufferCopyDataBytes(
                block,
                atOffset: 0,
                dataLength: count * MemoryLayout<Float>.stride,
                destination: destination
            )
            initializedCount = status == kCMBlockBufferNoErr ? count : 0
        }
    }
}

/// Contiguous mono audio at a position on the recording's timeline.
struct AudioBlock: Equatable, Sendable {
    /// Samples since the start of the timeline.
    let startSample: Int
    let samples: [Float]
}

/// Places decoded buffers on the recording's timeline, as blocks small enough to keep memory bounded on any length of
/// recording. Resampling can make a buffer's position disagree with the end of the last one by a few samples, and
/// capture can leave a real hole: small differences are evened out so that time never drifts, and a longer hole starts
/// a new block at its true position, without spending memory on the silence.
struct AudioTimelineAssembler {
    /// What speech recognition takes.
    static let sampleRate = 16_000
    /// A minute at a time keeps memory bounded and is plenty to choose chunk boundaries from.
    static let blockSamples = 60 * sampleRate
    /// Silence up to this long is written out, since it may be a dropped buffer in the middle of a word.
    static let maximumPaddedSamples = sampleRate

    private var startSample = 0
    private var pending: [Float] = []

    private var nextSample: Int {
        startSample + pending.count
    }

    /// Returns any blocks that are complete.
    mutating func append(_ samples: [Float], at position: Int) -> [AudioBlock] {
        var blocks: [AudioBlock] = []
        var incoming = samples[...]
        let offset = position - nextSample
        if pending.isEmpty, startSample == 0 {
            startSample = position
        } else if offset > Self.maximumPaddedSamples {
            blocks += finish()
            startSample = position
        } else if offset > 0 {
            pending.append(contentsOf: repeatElement(0, count: offset))
        } else if offset < 0 {
            incoming = incoming.dropFirst(-offset)
        }
        pending.append(contentsOf: incoming)
        while pending.count >= Self.blockSamples {
            blocks.append(AudioBlock(startSample: startSample, samples: Array(pending.prefix(Self.blockSamples))))
            pending.removeFirst(Self.blockSamples)
            startSample += Self.blockSamples
        }
        return blocks
    }

    /// Returns whatever is left, at the end of the audio or of a contiguous stretch.
    mutating func finish() -> [AudioBlock] {
        guard !pending.isEmpty else {
            return []
        }
        let block = AudioBlock(startSample: startSample, samples: pending)
        startSample += pending.count
        pending = []
        return [block]
    }
}
