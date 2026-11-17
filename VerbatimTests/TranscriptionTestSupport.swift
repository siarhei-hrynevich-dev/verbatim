import AVFoundation
import Foundation
import Synchronization

@testable import Verbatim

/// Stands in for inference. A call can be held open to observe what happens meanwhile, and it stops when cancelled the
/// way the real engine does, or ignores cancellation for a while as a Core ML prediction can.
final class FakeTranscriptionService: TranscriptionService {
    struct State {
        var output = TranscriptionOutput(
            speech: [RecognizedSpeech(startTime: 0, endTime: 2, text: "Hello there.", source: .microphone)],
            language: "en",
            modelVersion: "test",
            mediaDuration: 60
        )
        var failures: [any Error] = []
        var holdsCalls = false
        var ignoresCancellation = false
        var gates: [CheckedContinuation<Void, Never>] = []
        var requests: [TranscriptionRequest] = []
        var runningCount = 0
        var peakRunningCount = 0
        var releaseCount = 0
    }

    let state = Mutex(State())

    func update(_ change: (inout State) -> Void) {
        state.withLock { change(&$0) }
    }

    func read<Value: Sendable>(_ value: (State) -> Value) -> Value {
        state.withLock { value($0) }
    }

    /// Lets every held call continue.
    func releaseCalls() {
        let gates = state.withLock { state in
            defer {
                state.gates = []
                state.holdsCalls = false
            }
            return state.gates
        }
        gates.forEach { $0.resume() }
    }

    func transcribe(
        _ request: TranscriptionRequest,
        onUpdate: @escaping @Sendable (TranscriptionUpdate) -> Void
    ) async throws -> TranscriptionOutput {
        update {
            $0.requests.append(request)
            $0.runningCount += 1
            $0.peakRunningCount = max($0.peakRunningCount, $0.runningCount)
        }
        defer { update { $0.runningCount -= 1 } }
        onUpdate(.loadingModel)
        onUpdate(.processingAudio(fraction: 0.25))
        await hold()
        if !read(\.ignoresCancellation) {
            try Task.checkCancellation()
        }
        let failure = state.withLock { $0.failures.isEmpty ? nil : $0.failures.removeFirst() }
        if let failure {
            throw failure
        }
        onUpdate(.processingAudio(fraction: 1))
        return read(\.output)
    }

    func releaseModel() async {
        update { $0.releaseCount += 1 }
    }

    /// Waits at the gate if asked to, until released. Not ended by cancellation unless the fake is told to honor it.
    private func hold() async {
        guard read(\.holdsCalls) else {
            return
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let isHeld = state.withLock { state in
                    guard state.holdsCalls else {
                        return false
                    }
                    state.gates.append(continuation)
                    return true
                }
                if !isHeld {
                    continuation.resume()
                }
            }
        } onCancel: { [self] in
            if !read(\.ignoresCancellation) {
                releaseCalls()
            }
        }
    }
}

/// A model that is or isn't there, without `ModelManager`'s machinery.
@MainActor
final class FakeModelSource: TranscriptionModelSource {
    var failure: ModelManagementError?
    private(set) var leasesHeld = 0
    private(set) var prepareCount = 0

    func prepareForUse() async {
        prepareCount += 1
    }

    func acquireSelectedModel() throws(ModelManagementError) -> SpeechModelLease {
        if let failure {
            throw failure
        }
        leasesHeld += 1
        let model = ResolvedSpeechModel(
            id: "openai_whisper-tiny",
            modelFolder: URL(filePath: "/models/tiny", directoryHint: .isDirectory),
            tokenizerBase: URL(filePath: "/models", directoryHint: .isDirectory)
        )
        return SpeechModelLease(id: UUID(), model: model)
    }

    func release(_ lease: SpeechModelLease) {
        leasesHeld -= 1
    }
}

/// Transcript files that can fail, or a volume that can be full, with everything else real.
struct ConfigurableFileStore: TranscriptFileStore {
    let base = FileTranscriptStore()
    var writeError: (any Error)?
    var availableBytes: Int64 = 1_000_000_000_000

    func writeFiles(of transcript: Transcript, besideMediaAt mediaURL: URL) async throws {
        if let writeError {
            throw writeError
        }
        try await base.writeFiles(of: transcript, besideMediaAt: mediaURL)
    }

    func availableBytes(besideMediaAt mediaURL: URL) async -> Int64? {
        availableBytes
    }
}

/// A coordinator on a real database, Library and files in a temporary folder, with only inference and model replaced.
@MainActor
struct ProcessingTestEnvironment {
    let library: LibraryTestEnvironment
    let service: LibraryService
    let store: SQLiteTranscriptRepository
    let transcription: FakeTranscriptionService
    let models: FakeModelSource
    let coordinator: ProcessingCoordinator

    init(
        library environment: LibraryTestEnvironment? = nil,
        transcription: FakeTranscriptionService = FakeTranscriptionService(),
        models: FakeModelSource = FakeModelSource(),
        files: ConfigurableFileStore = ConfigurableFileStore(),
        language: TranscriptionLanguage = .automatic
    ) throws {
        let environment = try environment ?? LibraryTestEnvironment()
        library = environment
        let service = environment.makeService()
        self.service = service
        let store = SQLiteTranscriptRepository(databaseURL: environment.databaseURL)
        self.store = store
        self.transcription = transcription
        self.models = models
        coordinator = ProcessingCoordinator(
            dependencies: ProcessingCoordinator.Dependencies(
                jobs: store,
                transcripts: store,
                transcription: transcription,
                models: models,
                library: service,
                files: files,
                language: { language }
            )
        )
        service.addRemovalObserver(coordinator)
    }

    /// A restart: new objects on the same disk.
    func relaunched() throws -> ProcessingTestEnvironment {
        try ProcessingTestEnvironment(library: library, transcription: FakeTranscriptionService(), models: models)
    }

    @discardableResult
    func addRecording(title: String = "Demo") async throws -> LibraryRecording {
        let recording = try library.makeRecording(title: title)
        try await library.makeRepository().insert(recording)
        return recording
    }

    /// Waits for a condition on the main actor, failing rather than hanging if it never holds.
    func wait(until condition: () -> Bool) async throws {
        for _ in 0..<2_000 {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw TestError.failed
    }

    func waitUntilHeld() async throws {
        for _ in 0..<2_000 {
            if transcription.read({ !$0.gates.isEmpty }) {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw TestError.failed
    }
}

/// Media with named audio tracks, written faster than real time, whose tracks can start at different moments.
enum TranscriptionMediaFixture {
    struct Track {
        let source: AudioSourceKind?
        /// Where it starts on the recording's timeline, in seconds.
        let start: TimeInterval
        /// Each stretch of audio: where it starts relative to `start`, and how long it lasts.
        var stretches: [(offset: TimeInterval, seconds: TimeInterval)]
    }

    static func write(_ tracks: [Track], to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        var inputs: [AVAssetWriterInput] = []
        for track in tracks {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 64_000
                ]
            )
            input.expectsMediaDataInRealTime = false
            if let source = track.source {
                let item = AVMutableMetadataItem()
                item.identifier = .quickTimeUserDataTrackName
                item.value = CaptureAudioFormat.trackName(for: source) as NSString
                input.metadata = [item]
            }
            writer.add(input)
            inputs.append(input)
        }
        guard writer.startWriting() else {
            throw writer.error ?? TestError.failed
        }
        writer.startSession(atSourceTime: .zero)
        for (track, input) in zip(tracks, inputs) {
            for stretch in track.stretches {
                try await append(stretch, of: track, to: input)
            }
            input.markAsFinished()
        }
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? TestError.failed
        }
    }

    private static func append(
        _ stretch: (offset: TimeInterval, seconds: TimeInterval),
        of track: Track,
        to input: AVAssetWriterInput
    ) async throws {
        let bufferSeconds = 0.1
        for index in 0..<Int(stretch.seconds / bufferSeconds) {
            let time = track.start + stretch.offset + Double(index) * bufferSeconds
            let sample = try SyntheticSamples.audio(
                at: CMTime(seconds: time, preferredTimescale: 48_000),
                channels: 1,
                seconds: bufferSeconds
            )
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(1))
            }
            guard input.append(sample) else {
                throw TestError.failed
            }
        }
    }
}
