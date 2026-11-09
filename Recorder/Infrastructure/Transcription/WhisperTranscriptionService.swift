import Foundation
import OSLog
import WhisperKit

/// Offline recognition with WhisperKit, on models already installed. Downloads are off, and the model loads on the
/// first transcription and stays only until `releaseModel()`.
///
/// **Why not `transcribe(audioPath:)`.** It reads through `AVAudioFile`, which sees one track of a QuickTime file and
/// assumes audio starts at zero with no holes. Instead `RecordingAudioReader` decodes each track by its presentation
/// times and `SpeechChunker` applies WhisperKit's incremental loading rules, so the benefits of incremental loading
/// are kept: memory stays bounded on recordings of any length. No intermediate files are written.
///
/// **Cancellation.** Task cancellation is checked between chunks and between a chunk's windows, and the decoder's
/// callback stops its token loop early. A Core ML prediction already running cannot be interrupted, and neither can
/// loading a model, which can take minutes the first time Core ML compiles it. Callers must not wait on this.
actor WhisperTranscriptionService: TranscriptionService {
    private struct LoadedModel {
        let modelID: SpeechModel.ID
        let engine: WhisperKit
    }

    /// Marks a segment Whisper produces for audio with nothing to transcribe.
    private static let nonSpeechMarkers: Set<String> = ["[BLANK_AUDIO]", "(BLANK_AUDIO)"]

    private var loaded: LoadedModel?

    func transcribe(
        _ request: TranscriptionRequest,
        onUpdate: @escaping @Sendable (TranscriptionUpdate) -> Void
    ) async throws -> TranscriptionOutput {
        let layout = try await RecordingAudioLayout.inspect(request.mediaURL)
        onUpdate(.loadingModel)
        let model = try await load(request.model)
        try Task.checkCancellation()
        onUpdate(.processingAudio(fraction: 0))

        var collector = SpeechCollector(requestedLanguage: request.language.code)
        var progress = AudioProgress(layout: layout, onUpdate: onUpdate)
        for input in layout.inputs {
            try await transcribe(input, of: request, with: model, into: &collector, progress: &progress)
            progress.finish(input)
        }
        return TranscriptionOutput(
            speech: collector.speech,
            language: collector.language,
            modelVersion: model.modelVariant.description,
            mediaDuration: layout.mediaDuration
        )
    }

    func releaseModel() async {
        guard let loaded else {
            return
        }
        self.loaded = nil
        await loaded.engine.unloadModels()
    }

    // MARK: - Model

    private func load(_ model: ResolvedSpeechModel) async throws -> WhisperKit {
        if let loaded, loaded.modelID == model.id {
            return loaded.engine
        }
        await releaseModel()
        try Self.verifyAssets(of: model)
        let config = WhisperKitConfig(
            modelFolder: model.modelFolder.path(percentEncoded: false),
            tokenizerFolder: model.tokenizerBase,
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: true,
            download: false
        )
        do {
            let engine = try await WhisperKit(config)
            loaded = LoadedModel(modelID: model.id, engine: engine)
            return engine
        } catch {
            Self.logger.error("Could not load a speech model: \(String(describing: error))")
            throw TranscriptionFailure.modelLoadFailed(detail: error.localizedDescription)
        }
    }

    /// `ModelManager` checked these moments ago; this reports files gone since then as what they are.
    private static func verifyAssets(of model: ResolvedSpeechModel) throws {
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let path = model.modelFolder.appending(path: "\(component).mlmodelc", directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: path.path(percentEncoded: false)) else {
                throw TranscriptionFailure.modelUnavailable(model.id)
            }
        }
    }

    // MARK: - Recognition

    private func transcribe(
        _ input: RecordingAudioInput,
        of request: TranscriptionRequest,
        with model: WhisperKit,
        into collector: inout SpeechCollector,
        progress: inout AudioProgress
    ) async throws {
        let reader = try await RecordingAudioReader(url: request.mediaURL, input: input)
        var session = InputSession(input: input, requestedLanguage: request.language.code)
        var chunker = SpeechChunker(
            windowSamples: model.featureExtractor.windowSamples ?? Constants.defaultWindowSamples
        )

        while let block = try reader.nextBlock() {
            try Task.checkCancellation()
            try await handle(try await chunker.append(block), model, &session, &collector, &progress)
        }
        try await handle(try await chunker.finish(), model, &session, &collector, &progress)
        // A short input may end before enough speech arrived to settle its language.
        try await settleLanguage(model, &session, &collector, &progress)
    }

    /// Chunks wait until the language of this input is settled, then run in order.
    private func handle(
        _ chunks: [SpeechChunk],
        _ model: WhisperKit,
        _ session: inout InputSession,
        _ collector: inout SpeechCollector,
        _ progress: inout AudioProgress
    ) async throws {
        for chunk in chunks {
            if session.isSettlingLanguage {
                session.waiting.append(chunk)
                if session.waitingSpeechCount >= Tuning.languageProbeChunks {
                    try await settleLanguage(model, &session, &collector, &progress)
                }
            } else {
                try await recognize(chunk, model, &session, &collector, &progress)
            }
        }
    }

    /// Automatic detection decides once per input, from its first few stretches of speech, instead of once per chunk:
    /// a short or quiet chunk is easily taken for another language, and the whole chunk then decodes in it.
    private func settleLanguage(
        _ model: WhisperKit,
        _ session: inout InputSession,
        _ collector: inout SpeechCollector,
        _ progress: inout AudioProgress
    ) async throws {
        guard session.isSettlingLanguage else {
            return
        }
        session.language = try await detectLanguage(in: session.waiting, with: model)
        session.isSettlingLanguage = false
        let waiting = session.waiting
        session.waiting = []
        for chunk in waiting {
            try await recognize(chunk, model, &session, &collector, &progress)
        }
    }

    /// The language the chunks' speech most likely is. `nil` when nothing could be detected, which leaves each chunk to
    /// detect its own language as before.
    private func detectLanguage(in chunks: [SpeechChunk], with model: WhisperKit) async throws -> String? {
        var detections: [LanguageDetection] = []
        for chunk in chunks where !chunk.isSilent {
            try Task.checkCancellation()
            let audio = chunk.droppingLeadingSilence()
            do {
                let detected = try await model.detectLangauge(audioArray: audio.samples)
                let seconds = TimeInterval(audio.samples.count) / TimeInterval(AudioTimelineAssembler.sampleRate)
                detections += detected.langProbs.map {
                    LanguageDetection(language: $0.key, logProbability: $0.value, seconds: seconds)
                }
            } catch {
                Self.logger.error("Language detection failed: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
        return Self.mostLikelyLanguage(of: detections)
    }

    /// What WhisperKit's detection reports for one chunk: only the language it picked, with that pick's
    /// log-probability, not a distribution over languages.
    struct LanguageDetection: Equatable {
        let language: String
        let logProbability: Float
        let seconds: TimeInterval
    }

    /// Each chunk votes for its language with its probability, weighted by its length. Log-probabilities are never
    /// added up: they are negative, so a language picked by fewer chunks would score higher. Weighting by length keeps
    /// a short reply full of English terms in Russian speech from counting as much as a long stretch of speech.
    static func mostLikelyLanguage(of detections: [LanguageDetection]) -> String? {
        var votes: [String: Double] = [:]
        for detection in detections {
            votes[detection.language, default: 0] += exp(Double(detection.logProbability)) * max(detection.seconds, 0)
        }
        return votes.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    private func recognize(
        _ chunk: SpeechChunk,
        _ model: WhisperKit,
        _ session: inout InputSession,
        _ collector: inout SpeechCollector,
        _ progress: inout AudioProgress
    ) async throws {
        defer { progress.advance(session.input, toSample: chunk.startSample + chunk.samples.count) }
        try Task.checkCancellation()
        guard !chunk.isSilent else {
            return
        }
        let audio = chunk.droppingLeadingSilence()
        let options = Self.decodingOptions(language: session.language)
        let stopFlag = OSAllocatedUnfairLock(initialState: false)
        let results: [TranscriptionResult]
        do {
            results = try await withTaskCancellationHandler {
                try await model.transcribe(
                    audioArray: audio.samples,
                    decodeOptions: options,
                    callback: { _ in stopFlag.withLock { $0 } ? false : nil }
                )
            } onCancel: {
                stopFlag.withLock { $0 = true }
            }
        } catch let error as WhisperError {
            Self.logger.error("Recognition failed: \(error.localizedDescription, privacy: .public)")
            throw TranscriptionFailure.recognitionFailed(detail: error.localizedDescription)
        }
        // A stopped decoder returns what it had so far, which is not a result.
        try Task.checkCancellation()
        let chunkStart = TimeInterval(audio.startSample) / TimeInterval(AudioTimelineAssembler.sampleRate)
        for result in results {
            collector.add(result, source: session.input.source, chunkStart: chunkStart)
        }
    }

    /// Detection happens before decoding, once per input, so decoding itself is told the language. With none known,
    /// detection is requested explicitly: WhisperKit's default options would decode as English. Special tokens are
    /// left out of the text. Word timestamps cost a little time, but align each segment to its words: without them a
    /// segment can start seconds before anyone speaks, which is where selecting that line would seek to.
    ///
    /// Fallback is spelled out although these are WhisperKit's defaults: a window failing the thresholds is decoded
    /// again at a higher temperature, which is what ends repeated or invented text.
    private static func decodingOptions(language: String?) -> DecodingOptions {
        DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperature: 0,
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: 5,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            firstTokenLogProbThreshold: -1.5,
            noSpeechThreshold: Tuning.noSpeechThreshold
        )
    }

    static func isSpeech(_ text: String) -> Bool {
        guard !text.isEmpty, !nonSpeechMarkers.contains(text.uppercased()) else {
            return false
        }
        let lowered = text.lowercased()
        return !subtitleCredits.contains { lowered.hasPrefix($0) }
    }

    /// Credits Whisper learned from subtitled videos and writes over music or noise, never said by anyone here.
    private static let subtitleCredits = [
        "субтитры создавал", "субтитры сделал", "редактор субтитров", "корректор а.", "продолжение следует",
        "subtitles by", "subtitles created by", "thanks for watching", "amara.org"
    ]

    /// Whisper's own rule for a segment it probably invented: likely silence, and decoded with little confidence.
    /// Either alone is common in real speech; together they are how "Thanks for watching" appears over background
    /// noise. WhisperKit applies the threshold per window, so a segment inside an accepted window still needs this.
    static func isLikelyInvented(noSpeechProbability: Float, averageLogProbability: Float) -> Bool {
        noSpeechProbability > Tuning.noSpeechThreshold && averageLogProbability < Tuning.logProbThreshold
    }

    private enum Tuning {
        /// Stretches of speech whose language is averaged: about 90 seconds at most, held in memory until decided.
        static let languageProbeChunks = 3
        static let noSpeechThreshold: Float = 0.6
        static let logProbThreshold: Float = -1.0
    }

    private static let logger = Logger(subsystem: "dev.local.Recorder", category: "Transcription")
}

/// Adds up speech across chunks and sources, in recording time, and which language was heard most.
private struct SpeechCollector {
    let requestedLanguage: String?
    private(set) var speech: [RecognizedSpeech] = []
    private var secondsByLanguage: [String: TimeInterval] = [:]

    init(requestedLanguage: String?) {
        self.requestedLanguage = requestedLanguage
    }

    /// `nil` when no speech was found, since then nothing could be detected.
    var language: String? {
        if let requestedLanguage {
            return requestedLanguage
        }
        return secondsByLanguage.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    mutating func add(_ result: TranscriptionResult, source: TranscriptSource, chunkStart: TimeInterval) {
        for segment in result.segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard WhisperTranscriptionService.isSpeech(text) else {
                continue
            }
            guard
                !WhisperTranscriptionService.isLikelyInvented(
                    noSpeechProbability: segment.noSpeechProb,
                    averageLogProbability: segment.avgLogprob
                )
            else {
                continue
            }
            speech.append(
                RecognizedSpeech(
                    startTime: chunkStart + TimeInterval(segment.start),
                    endTime: chunkStart + TimeInterval(segment.end),
                    text: text,
                    source: source
                )
            )
            secondsByLanguage[result.language, default: 0] += TimeInterval(segment.end - segment.start)
        }
    }
}

/// What carries from one chunk of an input to the next.
private struct InputSession {
    let input: RecordingAudioInput
    /// `nil` while automatic detection has not decided, or could not.
    var language: String?
    var isSettlingLanguage: Bool
    /// Chunks held back until the language is settled.
    var waiting: [SpeechChunk] = []

    var waitingSpeechCount: Int {
        waiting.count { !$0.isSilent }
    }

    init(input: RecordingAudioInput, requestedLanguage: String?) {
        self.input = input
        language = requestedLanguage
        isSettlingLanguage = requestedLanguage == nil
    }
}

/// Measures progress as audio finished out of all audio to transcribe, across sources. Whisper's windows make it step
/// roughly every 30 seconds of audio.
private struct AudioProgress {
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
