import WhisperKit

/// A piece of audio a model can take in one pass.
struct SpeechChunk: Equatable, Sendable {
    /// Samples since the start of the recording's timeline.
    let startSample: Int
    let samples: [Float]

    /// Nothing to hear: digital silence, as before a track that starts late, or nothing sustained above the level of
    /// an idle microphone, whose clicks and hum reach about -50 dBFS (up to 9 windows of 50 ms in 30 seconds, where
    /// speech is about -30 and fills hundreds). A model given that writes words such as "Thank you.", so it isn't worth
    /// running. A chunk must have a few tenths of a second above the level, in total, rather than one loud instant.
    var isSilent: Bool {
        var loud = 0
        var windows = 0
        var start = 0
        while start < samples.count {
            let window = samples[start..<min(start + Self.levelWindowSamples, samples.count)]
            let meanSquare = window.reduce(Float(0)) { $0 + $1 * $1 } / Float(window.count)
            if meanSquare.squareRoot() >= Self.silenceLevel {
                loud += 1
            }
            windows += 1
            start += Self.levelWindowSamples
        }
        return loud < max(Self.minimumLoudWindows, min(Self.maximumLoudWindowsNeeded, windows / 4))
    }

    /// The same chunk from where its sound begins. Whisper tends to start its first segment at the start of what it is
    /// given, whatever comes first, so this keeps speech from being placed at the start of the silence before it.
    func droppingLeadingSilence() -> SpeechChunk {
        let silentCount = samples.prefix { abs($0) < Self.silenceAmplitude }.count
        return SpeechChunk(startSample: startSample + silentCount, samples: Array(samples.dropFirst(silentCount)))
    }

    private static let silenceAmplitude: Float = 0.000_1
    /// 50 ms.
    private static let levelWindowSamples = 800
    /// -50 dBFS RMS.
    private static let silenceLevel: Float = 0.003_16
    private static let minimumLoudWindows = 4
    private static let maximumLoudWindowsNeeded = 16
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
