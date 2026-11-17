import AVFoundation
import Foundation
import Testing

@testable import Verbatim

/// Real offline transcription with a model already on this Mac. Off unless asked for, because ordinary tests need no
/// models. Downloads nothing. Writes only to a temporary folder.
///
///     say -o /tmp/speech.aiff "Hello, this is a test of offline transcription."
///     TEST_RUNNER_RECORDER_E2E_MODELS=~/Library/Application\ Support/Verbatim/Models \
///     TEST_RUNNER_RECORDER_E2E_SPEECH=/tmp/speech.aiff make test
///
/// `TEST_RUNNER_RECORDER_E2E_LONG_MINUTES` also runs a recording of that length, reporting speed and peak memory.
@Suite(.enabled(if: WhisperEndToEndConfiguration.isConfigured), .serialized)
@MainActor
struct WhisperEndToEndTests {
    /// A model that is installed for the test, located the way `ModelFileStore` lays them out.
    private final class InstalledModel: TranscriptionModelSource {
        let model: ResolvedSpeechModel

        init(id: String, root: URL) {
            model = ResolvedSpeechModel(
                id: id,
                modelFolder: root.appending(
                    path: "models/argmaxinc/whisperkit-coreml/\(id)",
                    directoryHint: .isDirectory
                ),
                tokenizerBase: root
            )
        }

        func prepareForUse() async {}
        func acquireSelectedModel() throws(ModelManagementError) -> SpeechModelLease {
            SpeechModelLease(id: UUID(), model: model)
        }
        func release(_ lease: SpeechModelLease) {}
    }

    private let environment: LibraryTestEnvironment
    private let speechURL: URL
    private let model: InstalledModel
    private let service = WhisperTranscriptionService()

    init() throws {
        environment = try LibraryTestEnvironment()
        let values = ProcessInfo.processInfo.environment
        speechURL = URL(filePath: try #require(values["RECORDER_E2E_SPEECH"]))
        model = InstalledModel(
            id: values["RECORDER_E2E_MODEL_ID"] ?? "openai_whisper-tiny",
            root: URL(filePath: try #require(values["RECORDER_E2E_MODELS"]), directoryHint: .isDirectory)
        )
    }

    /// Writes the speech to a recording's tracks, each at its own position on the timeline.
    private func addRecording(
        tracks: [(source: AudioSourceKind, start: TimeInterval)],
        mode: CaptureMode = .audioOnly,
        roomToneSeconds: TimeInterval = 0,
        repeats: Int = 1
    ) async throws -> LibraryRecording {
        let id = UUID()
        let destination = try environment.makeRecordingFolder(id: id, createdAt: .now)
        try FileManager.default.removeItem(at: destination.mediaURL)
        try await SpeechRecordingFixture.write(
            speech: speechURL,
            tracks: tracks,
            roomToneSeconds: roomToneSeconds,
            repeats: repeats,
            to: destination.mediaURL
        )
        let duration = try await AVURLAsset(url: destination.mediaURL).load(.duration).seconds
        let recording = try LibraryRecording(
            recording: Recording(id: id, title: "Speech", duration: duration, processingStatus: .recorded),
            captureMode: mode,
            media: MediaReference(
                url: destination.mediaURL,
                bookmark: MediaFileAccess.bookmarkData(for: destination.mediaURL)
            ),
            fileSizeBytes: 1
        )
        try await environment.makeRepository().insert(recording)
        return recording
    }

    private struct Stack {
        let coordinator: ProcessingCoordinator
        let store: SQLiteTranscriptRepository
        let library: LibraryService
    }

    private func makeStack(language: TranscriptionLanguage = .automatic) -> Stack {
        let library = environment.makeService()
        let store = SQLiteTranscriptRepository(databaseURL: environment.databaseURL)
        let coordinator = ProcessingCoordinator(
            dependencies: ProcessingCoordinator.Dependencies(
                jobs: store,
                transcripts: store,
                transcription: service,
                models: model,
                library: library,
                files: FileTranscriptStore(),
                language: { language }
            )
        )
        return Stack(coordinator: coordinator, store: store, library: library)
    }

    @Test func aSpeechRecordingBecomesATranscriptThatSurvivesARestart() async throws {
        let recording = try await addRecording(tracks: [(.microphone, 0)])
        let stack = makeStack()
        let (coordinator, store, library) = (stack.coordinator, stack.store, stack.library)
        await coordinator.start()

        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()

        let job = try #require(coordinator.job(for: recording.id))
        #expect(job.state == .completed, "\(String(describing: job.failure))")
        let transcript = try #require(try await store.transcript(for: recording.id))
        Self.report(transcript)
        #expect(!transcript.segments.isEmpty)
        #expect(transcript.language == "en")
        #expect(transcript.modelVersion != nil)
        #expect(transcript.segments.map(\.text).joined(separator: " ").lowercased().contains("transcription"))
        #expect(transcript.segments.allSatisfy { !$0.text.contains("<|") })
        #expect(transcript.segments.allSatisfy { $0.source == .microphone })
        #expect(transcript.segments.allSatisfy { $0.endTime <= recording.recording.duration })

        let folder = recording.media.url.deletingLastPathComponent()
        for name in RecordingFileLayout.transcriptFileNames {
            let contents = try Data(contentsOf: folder.appending(path: name))
            #expect(!contents.isEmpty)
        }

        // A new launch: the same database and files, with new objects and no model loaded.
        let relaunched = makeStack().coordinator
        await relaunched.start()
        #expect(try await relaunched.transcript(for: recording.id) == transcript)

        // The Viewer on the real player: real lines, and a seek that lands where the line says.
        let viewer = ViewerViewModel(library: library, playback: AVPlaybackService(), processing: relaunched)
        viewer.open(recordingID: recording.id)
        await viewer.waitUntilSettled()
        #expect(viewer.lines.count == transcript.segments.count)
        let target = viewer.lines.count - 1
        viewer.seekToLine(at: target)
        await viewer.waitUntilSettled()
        #expect(abs(viewer.position - transcript.segments[target].startTime) < 0.01)
        #expect(viewer.activeLineIndex == target)
        viewer.windowClosed()

        // Re-transcribing replaces it whole.
        relaunched.enqueue(recording.id)
        await relaunched.waitUntilSettled()
        let replaced = try #require(try await relaunched.transcript(for: recording.id))
        #expect(!replaced.segments.isEmpty)
        #expect(replaced.segments.first?.id != transcript.segments.first?.id)
    }

    @Test func separateTracksKeepTheirSourcesAndOffsets() async throws {
        let offset: TimeInterval = 8
        let recording = try await addRecording(tracks: [(.microphone, 0), (.systemAudio, offset)], mode: .screen)
        let stack = makeStack()
        let (coordinator, store) = (stack.coordinator, stack.store)
        await coordinator.start()

        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()

        let transcript = try #require(try await store.transcript(for: recording.id))
        Self.report(transcript)
        let microphone = transcript.segments.filter { $0.source == .microphone }
        let system = transcript.segments.filter { $0.source == .systemAudio }
        let firstMicrophone = try #require(microphone.first)
        let firstSystem = try #require(system.first)
        #expect(firstSystem.startTime - firstMicrophone.startTime > offset - 1.5)
        #expect(firstSystem.startTime - firstMicrophone.startTime < offset + 1.5)
        expectChronological(transcript)
    }

    @Test func speechAfterQuietRoomToneStartsWhereItIsSpoken() async throws {
        let roomTone: TimeInterval = 6
        let recording = try await addRecording(tracks: [(.microphone, 0)], roomToneSeconds: roomTone)
        let stack = makeStack()
        let (coordinator, store) = (stack.coordinator, stack.store)
        await coordinator.start()

        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()

        let transcript = try #require(try await store.transcript(for: recording.id))
        Self.report(transcript)
        let first = try #require(transcript.segments.first)
        #expect(abs(first.startTime - roomTone) < 1.5)
    }

    @Test func speechAcrossManyChunksStaysInOrderWithoutRepeats() async throws {
        let recording = try await addRecording(tracks: [(.microphone, 0)], roomToneSeconds: 1, repeats: 8)
        let stack = makeStack()
        let (coordinator, store) = (stack.coordinator, stack.store)
        await coordinator.start()

        coordinator.enqueue(recording.id)
        await coordinator.waitUntilSettled()

        let transcript = try #require(try await store.transcript(for: recording.id))
        expectChronological(transcript)
        for (current, next) in zip(transcript.segments, transcript.segments.dropFirst()) {
            #expect(current.endTime <= next.startTime + 0.001)
        }
        let text = transcript.segments.map(\.text).joined(separator: " ").lowercased()
        let spoken = text.components(separatedBy: "thank you for listening").count - 1
        #expect(spoken == 8, "Heard \(spoken) repeats in \(transcript.segments.count) segments")
    }

    @Test(.enabled(if: WhisperEndToEndConfiguration.longMinutes != nil))
    func aLongRecordingStaysWithinBoundedMemory() async throws {
        let minutes = try #require(WhisperEndToEndConfiguration.longMinutes)
        let speechSeconds = try await AVURLAsset(url: speechURL).load(.duration).seconds
        let repeats = Int(Double(minutes) * 60 / (speechSeconds + 1))
        let recording = try await addRecording(tracks: [(.microphone, 0)], roomToneSeconds: 1, repeats: repeats)
        let stack = makeStack()
        let (coordinator, store) = (stack.coordinator, stack.store)
        await coordinator.start()
        let startedAt = Date.now
        let before = MemoryFootprint.currentBytes

        coordinator.enqueue(recording.id)
        var peak = before
        while coordinator.job(for: recording.id)?.state.isActive == true {
            peak = max(peak, MemoryFootprint.currentBytes)
            try await Task.sleep(for: .milliseconds(200))
        }
        await coordinator.waitUntilSettled()

        let transcript = try #require(try await store.transcript(for: recording.id))
        let elapsed = Date.now.timeIntervalSince(startedAt)
        print("E2E long: \(recording.recording.duration) s of audio in \(elapsed) s")
        print("E2E long: \(transcript.segments.count) segments, \(before / 1_000_000) → \(peak / 1_000_000) MB")
        #expect(coordinator.job(for: recording.id)?.state == .completed)
        expectChronological(transcript)
        #expect(peak - before < 500_000_000)
    }

    @Test func anExplicitLanguageIsUsedAndAMissingModelIsReported() async throws {
        let recording = try await addRecording(tracks: [(.microphone, 0)])
        let stack = makeStack(language: .explicit(code: "en"))
        let (english, store) = (stack.coordinator, stack.store)
        await english.start()
        english.enqueue(recording.id)
        await english.waitUntilSettled()
        #expect(try await store.transcript(for: recording.id)?.language == "en")

        let missing = ResolvedSpeechModel(
            id: "openai_whisper-missing",
            modelFolder: environment.root.appending(path: "nothing", directoryHint: .isDirectory),
            tokenizerBase: environment.root
        )
        await #expect(throws: TranscriptionFailure.modelUnavailable(missing.id)) {
            _ = try await service.transcribe(
                TranscriptionRequest(
                    recordingID: recording.id,
                    mediaURL: recording.media.url,
                    model: missing,
                    language: .automatic
                ),
                onUpdate: { _ in }
            )
        }
    }

    @Test func cancellingStopsWithCancellationAndTheEngineCanRunAgain() async throws {
        let recording = try await addRecording(tracks: [(.microphone, 0)])
        let request = TranscriptionRequest(
            recordingID: recording.id,
            mediaURL: recording.media.url,
            model: model.model,
            language: .automatic
        )
        let service = service
        let running = Task {
            try await service.transcribe(request, onUpdate: { _ in })
        }
        running.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await running.value
        }

        let output = try await service.transcribe(request, onUpdate: { _ in })
        #expect(!output.speech.isEmpty)
        await service.releaseModel()
    }

    /// Timings and text of synthetic speech, for reading the test log. Never real recordings.
    private static func report(_ transcript: Transcript) {
        for segment in transcript.segments {
            print("E2E [\(segment.startTime)-\(segment.endTime)] \(segment.source.rawValue): \(segment.text)")
        }
    }

    private func expectChronological(_ transcript: Transcript) {
        let starts = transcript.segments.map(\.startTime)
        #expect(starts == starts.sorted())
    }
}

private enum WhisperEndToEndConfiguration {
    static var isConfigured: Bool {
        let values = ProcessInfo.processInfo.environment
        return values["RECORDER_E2E_MODELS"] != nil && values["RECORDER_E2E_SPEECH"] != nil
    }

    static var longMinutes: Int? {
        ProcessInfo.processInfo.environment["RECORDER_E2E_LONG_MINUTES"].flatMap(Int.init)
    }
}

private enum MemoryFootprint {
    /// The same figure Activity Monitor shows as Memory.
    static var currentBytes: Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }
}
