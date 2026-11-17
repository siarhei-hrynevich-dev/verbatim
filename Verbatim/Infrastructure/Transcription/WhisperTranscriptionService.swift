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

    /// Automatic detection settles the input's language from its first few stretches of speech, not from one chunk: a
    /// short or quiet chunk is easily taken for another language. Their detections are kept, since each chunk is
    /// detected again when it is decoded (see `LanguageChoice`).
    private func settleLanguage(
        _ model: WhisperKit,
        _ session: inout InputSession,
        _ collector: inout SpeechCollector,
        _ progress: inout AudioProgress
    ) async throws {
        guard session.isSettlingLanguage else {
            return
        }
        var detections: [LanguageDetection?] = []
        for chunk in session.waiting {
            detections.append(
                chunk.isSilent ? nil : try await detectLanguage(of: chunk.droppingLeadingSilence(), model)
            )
        }
        session.trackLanguage = LanguageChoice.trackLanguage(of: detections.compactMap(\.self))
        session.isSettlingLanguage = false
        let waiting = session.waiting
        session.waiting = []
        for (chunk, detection) in zip(waiting, detections) {
            try await recognize(chunk, model, &session, &collector, &progress, detection: detection)
        }
    }

    /// `nil` when detection failed, which is logged: the chunk then keeps the input's language.
    private func detectLanguage(of audio: SpeechChunk, _ model: WhisperKit) async throws -> LanguageDetection? {
        try Task.checkCancellation()
        do {
            let detected = try await model.detectLangauge(audioArray: audio.samples)
            guard let logProbability = detected.langProbs[detected.language] else {
                return nil
            }
            let seconds = TimeInterval(audio.samples.count) / TimeInterval(AudioTimelineAssembler.sampleRate)
            return LanguageDetection(language: detected.language, logProbability: logProbability, seconds: seconds)
        } catch {
            Self.logger.error("Language detection failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The language to decode a chunk in: the requested one, or with automatic detection the chunk's own when it is
    /// clearly another than the input's. `nil` leaves the decoder to detect it, when the input's could not be.
    private func language(
        of audio: SpeechChunk,
        _ model: WhisperKit,
        _ session: InputSession,
        detection: LanguageDetection?
    ) async throws -> String? {
        guard session.isAutomatic, let trackLanguage = session.trackLanguage else {
            return session.trackLanguage
        }
        var detection = detection
        if detection == nil {
            detection = try await detectLanguage(of: audio, model)
        }
        let language = LanguageChoice.chunkLanguage(detection, trackLanguage: trackLanguage)
        if language != trackLanguage, let detection {
            let seconds = TimeInterval(audio.startSample) / TimeInterval(AudioTimelineAssembler.sampleRate)
            let probability = detection.probability
            Self.logger.info(
                """
                Chunk at \(seconds, format: .fixed(precision: 1), privacy: .public) s switches from \
                \(trackLanguage, privacy: .public) to \(language, privacy: .public), \
                p = \(probability, format: .fixed(precision: 2), privacy: .public)
                """
            )
        }
        return language
    }

    private func recognize(
        _ chunk: SpeechChunk,
        _ model: WhisperKit,
        _ session: inout InputSession,
        _ collector: inout SpeechCollector,
        _ progress: inout AudioProgress,
        detection: LanguageDetection? = nil
    ) async throws {
        defer { progress.advance(session.input, toSample: chunk.startSample + chunk.samples.count) }
        try Task.checkCancellation()
        guard !chunk.isSilent else {
            return
        }
        let audio = chunk.droppingLeadingSilence()
        let options = Self.decodingOptions(
            language: try await language(of: audio, model, session, detection: detection)
        )
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

    /// Detection happens before decoding, so decoding itself is told the language. With none known,
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

    private static let logger = Logger(category: "Transcription")
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
    /// No language was requested, so it is detected.
    let isAutomatic: Bool
    /// The requested language, or the one detected for the input. `nil` while automatic detection has not decided, or
    /// could not.
    var trackLanguage: String?
    var isSettlingLanguage: Bool
    /// Chunks held back until the language is settled.
    var waiting: [SpeechChunk] = []

    var waitingSpeechCount: Int {
        waiting.count { !$0.isSilent }
    }

    init(input: RecordingAudioInput, requestedLanguage: String?) {
        self.input = input
        isAutomatic = requestedLanguage == nil
        trackLanguage = requestedLanguage
        isSettlingLanguage = requestedLanguage == nil
    }
}
