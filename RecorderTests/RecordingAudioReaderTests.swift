import AVFoundation
import Foundation
import Testing

@testable import Recorder

/// The real decoder and chunker on media written for each test. Nothing here loads a model.
struct RecordingAudioReaderTests {
    let environment: LibraryTestEnvironment

    init() throws {
        environment = try LibraryTestEnvironment()
    }

    private func media(_ tracks: [TranscriptionMediaFixture.Track]) async throws -> URL {
        let url = environment.root.appending(path: "\(UUID()).mov")
        try await TranscriptionMediaFixture.write(tracks, to: url)
        return url
    }

    private func blocks(of input: RecordingAudioInput, in url: URL) async throws -> [AudioBlock] {
        let reader = try await RecordingAudioReader(url: url, input: input)
        var blocks: [AudioBlock] = []
        while let block = try reader.nextBlock() {
            blocks.append(block)
        }
        return blocks
    }

    private func seconds(_ samples: Int) -> Double {
        Double(samples) / Double(AudioTimelineAssembler.sampleRate)
    }

    // MARK: - Layout

    @Test func namedTracksAreTranscribedSeparately() async throws {
        let url = try await media([
            .init(source: .microphone, start: 0, stretches: [(0, 2)]),
            .init(source: .systemAudio, start: 0, stretches: [(0, 2)])
        ])

        let layout = try await RecordingAudioLayout.inspect(url)

        #expect(layout.inputs.map(\.source) == [.microphone, .systemAudio])
        #expect(layout.inputs.allSatisfy { $0.trackIDs.count == 1 })
    }

    @Test func aFileFromTheRealWriterIsRecognized() async throws {
        let url = try await environment.writePlayableMedia(hasVideo: true)

        let layout = try await RecordingAudioLayout.inspect(url)

        #expect(layout.inputs.map(\.source) == [.microphone])
        let blocks = try await blocks(of: try #require(layout.inputs.first), in: url)
        #expect(blocks.flatMap(\.samples).count > AudioTimelineAssembler.sampleRate / 2)
    }

    @Test func tracksThatCannotBeToldApartAreMixedAndLabeledUnknown() async throws {
        let url = try await media([
            .init(source: nil, start: 0, stretches: [(0, 1)]),
            .init(source: nil, start: 0, stretches: [(0, 1)])
        ])

        let layout = try await RecordingAudioLayout.inspect(url)

        #expect(layout.inputs.map(\.source) == [.unknown])
        #expect(layout.inputs.first?.trackIDs.count == 2)
        let blocks = try await blocks(of: try #require(layout.inputs.first), in: url)
        #expect(abs(seconds(blocks.flatMap(\.samples).count) - 1) < 0.2)
    }

    @Test func oneNamedAndOneUnnamedTrackAreMixedRatherThanGuessed() async throws {
        let url = try await media([
            .init(source: .microphone, start: 0, stretches: [(0, 1)]),
            .init(source: nil, start: 0, stretches: [(0, 1)])
        ])

        let layout = try await RecordingAudioLayout.inspect(url)

        #expect(layout.inputs.map(\.source) == [.unknown])
    }

    @Test func aVideoWithoutSoundHasNothingToTranscribe() async throws {
        let url = environment.root.appending(path: "\(UUID()).mov")
        let writer = try MediaFileWriter(
            url: url,
            video: .init(size: PixelSize(width: 320, height: 180), frameRate: .fps30),
            audioSources: []
        )
        for index in 0..<10 {
            let time = CMTime(seconds: Double(index) / 30, preferredTimescale: 600)
            writer.appendVideoFrame(try SyntheticSamples.videoFrame(at: time))
        }
        try await writer.finish(stopTime: CMTime(seconds: 0.5, preferredTimescale: 600))

        await #expect(throws: TranscriptionFailure.noAudio) {
            _ = try await RecordingAudioLayout.inspect(url)
        }
    }

    @Test func aFileThatIsNotMediaIsReportedAsUnsupported() async throws {
        let url = environment.root.appending(path: "\(UUID()).mov")
        try Data(repeating: 1, count: 2_048).write(to: url)

        await #expect {
            _ = try await RecordingAudioLayout.inspect(url)
        } throws: { error in
            if case TranscriptionFailure.unsupportedAudio = error {
                return true
            }
            return false
        }
    }

    // MARK: - Timestamps

    @Test func audioIsDecodedAtTheRateRecognitionTakes() async throws {
        let url = try await media([.init(source: .microphone, start: 0, stretches: [(0, 5)])])
        let layout = try await RecordingAudioLayout.inspect(url)

        let samples = try await blocks(of: try #require(layout.inputs.first), in: url).flatMap(\.samples)

        #expect(abs(seconds(samples.count) - 5) < 0.1)
        #expect(samples.contains { abs($0) > 0.05 })
    }

    @Test func aTrackStartingLateKeepsItsPlaceOnTheTimeline() async throws {
        let url = try await media([
            .init(source: .microphone, start: 0, stretches: [(0, 1)]),
            .init(source: .systemAudio, start: 7, stretches: [(0, 1)])
        ])
        let layout = try await RecordingAudioLayout.inspect(url)

        let microphone = try await blocks(of: layout.inputs[0], in: url)
        let system = try await blocks(of: layout.inputs[1], in: url)

        #expect(try #require(firstSoundSeconds(in: microphone)) < 0.1)
        #expect(abs(try #require(firstSoundSeconds(in: system)) - 7) < 0.1)
    }

    @Test func aSessionNotStartingAtZeroStillReadsFromTheMediasOwnTimeline() async throws {
        let url = try await environment.writePlayableMedia(hasVideo: false)
        let layout = try await RecordingAudioLayout.inspect(url)

        let blocks = try await blocks(of: try #require(layout.inputs.first), in: url)

        #expect(try #require(firstSoundSeconds(in: blocks)) < 0.1)
    }

    private func firstSoundSeconds(in blocks: [AudioBlock]) -> Double? {
        for block in blocks {
            if let index = block.samples.firstIndex(where: { abs($0) > 0.05 }) {
                return seconds(block.startSample + index)
            }
        }
        return nil
    }

    @Test func silenceAndInaudibleNoiseCountAsSilent() {
        let silence = [Float](repeating: 0, count: 16_000)
        let word = [Float](repeating: 0.05, count: 8_000)
        #expect(SpeechChunk(startSample: 0, samples: silence).isSilent)
        #expect(!SpeechChunk(startSample: 0, samples: silence + word).isSilent)
    }

    @Test func aChunkStartsWhereItsSoundDoes() {
        let chunk = SpeechChunk(startSample: 100, samples: [0, 0, 0, 0.5, 0, 0.5])

        #expect(chunk.droppingLeadingSilence() == SpeechChunk(startSample: 103, samples: [0.5, 0, 0.5]))
    }

    // MARK: - Assembling the timeline

    @Test func buffersFollowingOnFormOneBlock() {
        var timeline = AudioTimelineAssembler()

        #expect(timeline.append([1, 2], at: 100).isEmpty)
        #expect(timeline.append([3, 4], at: 102).isEmpty)

        #expect(timeline.finish() == [AudioBlock(startSample: 100, samples: [1, 2, 3, 4])])
    }

    @Test func aSmallGapIsFilledWithSilenceAndAnOverlapIsTrimmed() {
        var timeline = AudioTimelineAssembler()

        _ = timeline.append([1, 1], at: 0)
        _ = timeline.append([2, 2], at: 4)
        _ = timeline.append([3, 3], at: 5)

        #expect(timeline.finish() == [AudioBlock(startSample: 0, samples: [1, 1, 0, 0, 2, 2, 3])])
    }

    @Test func aLongGapStartsANewBlockAtItsTruePosition() {
        var timeline = AudioTimelineAssembler()
        _ = timeline.append([1], at: 0)
        let position = AudioTimelineAssembler.maximumPaddedSamples * 10

        let finished = timeline.append([2], at: position)

        #expect(finished == [AudioBlock(startSample: 0, samples: [1])])
        #expect(timeline.finish() == [AudioBlock(startSample: position, samples: [2])])
    }

    @Test func blocksStayBoundedHoweverLongTheAudio() {
        var timeline = AudioTimelineAssembler()
        var blocks: [AudioBlock] = []
        let buffer = [Float](repeating: 0.1, count: AudioTimelineAssembler.sampleRate)

        for second in 0..<150 {
            blocks += timeline.append(buffer, at: second * AudioTimelineAssembler.sampleRate)
        }
        blocks += timeline.finish()

        #expect(blocks.allSatisfy { $0.samples.count <= AudioTimelineAssembler.blockSamples })
        #expect(blocks.map(\.startSample) == [0, 960_000, 1_920_000])
        #expect(blocks.reduce(0) { $0 + $1.samples.count } == 150 * AudioTimelineAssembler.sampleRate)
    }

    // MARK: - Chunking

    private let window = 480_000

    private func chunks(of blocks: [AudioBlock]) async throws -> [SpeechChunk] {
        var chunker = SpeechChunker(windowSamples: window)
        var chunks: [SpeechChunk] = []
        for block in blocks {
            chunks += try await chunker.append(block)
        }
        chunks += try await chunker.finish()
        return chunks
    }

    private func tone(samples: Int) -> [Float] {
        (0..<samples).map { sin(Float($0) * 0.05) * 0.3 }
    }

    @Test func shortAudioIsOneChunkAtItsPosition() async throws {
        let chunks = try await chunks(of: [AudioBlock(startSample: 8_000, samples: tone(samples: 32_000))])

        #expect(chunks.map(\.startSample) == [8_000])
        #expect(chunks.first?.samples.count == 32_000)
    }

    @Test func longAudioIsCutIntoOrderedChunksThatNeverOverlapOrExceedAWindow() async throws {
        var blocks: [AudioBlock] = []
        let block = tone(samples: AudioTimelineAssembler.blockSamples)
        for index in 0..<5 {
            blocks.append(AudioBlock(startSample: index * block.count, samples: block))
        }

        let chunks = try await chunks(of: blocks)

        #expect(chunks.count >= 10)
        #expect(chunks.allSatisfy { $0.samples.count <= window })
        for (current, next) in zip(chunks, chunks.dropFirst()) {
            #expect(current.startSample + current.samples.count == next.startSample)
        }
        #expect(chunks.first?.startSample == 0)
    }

    @Test func chunksPreferCuttingAtSilence() async throws {
        var samples = tone(samples: 25 * 16_000)
        samples += [Float](repeating: 0, count: 2 * 16_000)
        samples += tone(samples: 25 * 16_000)

        let chunks = try await chunks(of: [AudioBlock(startSample: 0, samples: samples)])

        let cut = try #require(chunks.first).samples.count
        #expect(cut > 25 * 16_000 && cut < 27 * 16_000)
    }

    @Test func audioAfterAHoleKeepsItsPosition() async throws {
        let later = 3_000_000
        let chunks = try await chunks(of: [
            AudioBlock(startSample: 0, samples: tone(samples: 40_000)),
            AudioBlock(startSample: later, samples: tone(samples: 40_000))
        ])

        #expect(chunks.map(\.startSample) == [0, later])
    }
}
