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
        let options = Self.decodingOptions(for: request.language)
        var chunker = SpeechChunker(
            windowSamples: model.featureExtractor.windowSamples ?? Constants.defaultWindowSamples
        )

        while let block = try reader.nextBlock() {
            try Task.checkCancellation()
            for chunk in try await chunker.append(block) {
                try await recognize(chunk, of: input, with: model, options: options, into: &collector)
                progress.advance(input, toSample: chunk.startSample + chunk.samples.count)
            }
        }
        for chunk in try await chunker.finish() {
            try await recognize(chunk, of: input, with: model, options: options, into: &collector)
            progress.advance(input, toSample: chunk.startSample + chunk.samples.count)
        }
    }

    private func recognize(
        _ chunk: SpeechChunk,
        of input: RecordingAudioInput,
        with model: WhisperKit,
        options: DecodingOptions,
        into collector: inout SpeechCollector
    ) async throws {
        try Task.checkCancellation()
        guard !chunk.isSilent else {
            return
        }
        let audio = chunk.droppingLeadingSilence()
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
            collector.add(result, source: input.source, chunkStart: chunkStart)
        }
    }

    /// Language detection is requested explicitly: WhisperKit's default options would decode as English. Special tokens
    /// are left out of the text. Word timestamps cost a little time, but align each segment to its words: without them
    /// a segment can start seconds before anyone speaks, which is where selecting that line would seek to.
    private static func decodingOptions(for language: TranscriptionLanguage) -> DecodingOptions {
        DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language.code,
            usePrefillPrompt: true,
            detectLanguage: language == .automatic,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true
        )
    }

    fileprivate static func isSpeech(_ text: String) -> Bool {
        !text.isEmpty && !nonSpeechMarkers.contains(text.uppercased())
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
