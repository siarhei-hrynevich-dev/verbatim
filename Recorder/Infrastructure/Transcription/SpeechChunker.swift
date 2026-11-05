import WhisperKit

/// A piece of audio a model can take in one pass.
struct SpeechChunk: Equatable, Sendable {
    /// Samples since the start of the recording's timeline.
    let startSample: Int
    let samples: [Float]

    /// Nothing but digital silence, as before a track that starts late. Nothing can be heard in it, and a model given
    /// silence can imagine words, so it isn't worth running. Quiet rooms are not this quiet.
    var isSilent: Bool {
        samples.allSatisfy { abs($0) < Self.silenceAmplitude }
    }

    /// The same chunk from where its sound begins. Whisper tends to start its first segment at the start of what it is
    /// given, whatever comes first, so this keeps speech from being placed at the start of the silence before it.
    func droppingLeadingSilence() -> SpeechChunk {
        let silentCount = samples.prefix { abs($0) < Self.silenceAmplitude }.count
        return SpeechChunk(startSample: startSample + silentCount, samples: Array(samples.dropFirst(silentCount)))
    }

    private static let silenceAmplitude: Float = 0.000_1
}

/// Cuts audio into chunks no longer than a model's window, at silences where it can, using the same chunker and rules
/// as WhisperKit's own incremental file loading. Holds at most a block plus a window, so memory stays bounded.
///
/// A chunk is only given out once enough audio has arrived to be sure of its end. Chunks never overlap and stay in
/// order, which is what keeps speech at their boundaries from being repeated or misplaced.
struct SpeechChunker {
    private let windowSamples: Int
    private var startSample = 0
    private var pending: [Float] = []

    init(windowSamples: Int) {
        self.windowSamples = windowSamples
    }

    /// Returns the chunks now decided. A block not following directly on the last, after a hole in the audio, ends what
    /// came before it.
    mutating func append(_ block: AudioBlock) async throws -> [SpeechChunk] {
        var chunks: [SpeechChunk] = []
        if startSample + pending.count != block.startSample {
            chunks += try await finish()
            startSample = block.startSample
        }
        pending.append(contentsOf: block.samples)
        guard pending.count > windowSamples else {
            return chunks
        }
        let decided = try await cut().filter { $0.seekOffsetIndex + windowSamples <= pending.count }
        guard let last = decided.last else {
            return chunks
        }
        chunks += decided.map(chunk(from:))
        consume(last.seekOffsetIndex + last.audioSamples.count)
        return chunks
    }

    /// Returns everything that remains.
    mutating func finish() async throws -> [SpeechChunk] {
        guard !pending.isEmpty else {
            return []
        }
        let chunks = try await cut().map(chunk(from:))
        consume(pending.count)
        return chunks
    }

    private func cut() async throws -> [AudioChunk] {
        try await VADAudioChunker().chunkAll(audioArray: pending, maxChunkLength: windowSamples, decodeOptions: nil)
    }

    private func chunk(from chunk: AudioChunk) -> SpeechChunk {
        SpeechChunk(startSample: startSample + chunk.seekOffsetIndex, samples: chunk.audioSamples)
    }

    private mutating func consume(_ count: Int) {
        pending.removeFirst(count)
        startSample += count
    }
}
