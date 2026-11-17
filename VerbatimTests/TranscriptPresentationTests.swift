import Foundation
import Testing

@testable import Verbatim

/// The Viewer and the Library showing real jobs and transcripts, on a real database and coordinator.
@MainActor
struct ViewerTranscriptTests {
    let environment: ProcessingTestEnvironment
    let playback = FakePlaybackService()
    let viewModel: ViewerViewModel

    init() async throws {
        environment = try ProcessingTestEnvironment()
        await environment.coordinator.start()
        viewModel = ViewerViewModel(
            library: environment.service,
            playback: playback,
            processing: environment.coordinator
        )
        environment.transcription.update {
            $0.output = TranscriptionOutput(
                speech: [
                    RecognizedSpeech(startTime: 0, endTime: 4, text: "First words", source: .microphone),
                    RecognizedSpeech(startTime: 5, endTime: 9, text: "Second words", source: .systemAudio),
                    RecognizedSpeech(startTime: 20, endTime: 24, text: "Third line", source: .microphone)
                ],
                language: "en",
                modelVersion: "tiny",
                mediaDuration: 60
            )
        }
    }

    private func transcribedAndOpened() async throws -> LibraryRecording {
        let recording = try await environment.addRecording()
        environment.coordinator.enqueue(recording.id)
        await environment.coordinator.waitUntilSettled()
        viewModel.open(recordingID: recording.id)
        await viewModel.waitUntilSettled()
        return recording
    }

    // MARK: - Showing

    @Test func aStoredTranscriptAppearsWithSourcesAndTimes() async throws {
        _ = try await transcribedAndOpened()

        #expect(viewModel.recording?.transcriptState == .ready)
        #expect(viewModel.lines.map(\.text) == ["First words", "Second words", "Third line"])
        #expect(viewModel.lines.map(\.start) == [0, 5, 20])
        #expect(viewModel.lines.map(\.speaker) == [.you, .systemAudio, .you])
        #expect(viewModel.recording?.language.isEmpty == false)
        #expect(viewModel.canShowTranscriptInFinder)
    }

    @Test func noTranscriptOffersGeneratingOne() async throws {
        let recording = try await environment.addRecording()
        viewModel.open(recordingID: recording.id)
        await viewModel.waitUntilSettled()

        #expect(viewModel.recording?.transcriptState == .notProcessed)
        #expect(viewModel.transcriptionActionTitle == String(localized: "Generate Transcript"))
        #expect(viewModel.transcriptActivity == nil)

        viewModel.startProcessing()
        await environment.coordinator.waitUntilSettled()
        await viewModel.refreshMetadata()

        #expect(viewModel.lines.count == 3)
        #expect(viewModel.transcriptionActionTitle == String(localized: "Re-transcribe"))
    }

    @Test func aRunningJobShowsItsRealProgressAndCanBeCancelled() async throws {
        let recording = try await environment.addRecording()
        viewModel.open(recordingID: recording.id)
        await viewModel.waitUntilSettled()
        environment.transcription.update { $0.holdsCalls = true }

        viewModel.startProcessing()
        try await environment.waitUntilHeld()
        try await environment.wait {
            viewModel.transcriptActivity == .running(.processingAudio(progress: 0.25))
        }
        #expect(viewModel.transcriptionActionTitle == nil)

        viewModel.cancelProcessing()
        #expect(viewModel.transcriptActivity == .stopping)
        await environment.coordinator.waitUntilSettled()

        #expect(viewModel.transcriptActivity == nil)
        #expect(viewModel.lines.isEmpty)
    }

    @Test func aFailureShowsItsReasonAndOffersRetry() async throws {
        let recording = try await environment.addRecording()
        environment.models.failure = .noModelSelected
        environment.coordinator.enqueue(recording.id)
        await environment.coordinator.waitUntilSettled()

        viewModel.open(recordingID: recording.id)
        await viewModel.waitUntilSettled()

        guard case .failed(let issue) = viewModel.transcriptActivity else {
            Issue.record("Expected a failure")
            return
        }
        #expect(issue.recovery == .openSettings)
        #expect(viewModel.transcriptionActionTitle == String(localized: "Retry Transcription"))
    }

    @Test func aRecordingWithNoSpeechSaysSoRatherThanOfferingToStart() async throws {
        environment.transcription.update {
            $0.output = TranscriptionOutput(speech: [], language: nil, modelVersion: nil, mediaDuration: 60)
        }

        _ = try await transcribedAndOpened()

        #expect(viewModel.hasEmptyTranscript)
        #expect(viewModel.transcriptionActionTitle == String(localized: "Re-transcribe"))
    }

    @Test func theOldTranscriptStaysOnScreenWhileAReplacementRuns() async throws {
        _ = try await transcribedAndOpened()
        environment.transcription.update { $0.holdsCalls = true }

        viewModel.startProcessing()
        try await environment.waitUntilHeld()
        await viewModel.refreshMetadata()

        #expect(viewModel.lines.count == 3)
        #expect(viewModel.recording?.hasTranscript == true)
        environment.transcription.releaseCalls()
        await environment.coordinator.waitUntilSettled()
    }

    @Test func aNewTranscriptReplacesWhatIsShowingWhenItIsDone() async throws {
        _ = try await transcribedAndOpened()
        environment.transcription.update {
            $0.output = TranscriptionOutput(
                speech: [RecognizedSpeech(startTime: 1, endTime: 2, text: "Replacement", source: .microphone)],
                language: "de",
                modelVersion: "base",
                mediaDuration: 60
            )
        }

        viewModel.startProcessing()
        await environment.coordinator.waitUntilSettled()
        await viewModel.refreshMetadata()

        #expect(viewModel.lines.map(\.text) == ["Replacement"])
    }

    @Test func theTranscriptIsStillThereAfterARestart() async throws {
        let recording = try await transcribedAndOpened()

        let next = try environment.relaunched()
        await next.coordinator.start()
        let reopened = ViewerViewModel(library: next.service, playback: playback, processing: next.coordinator)
        reopened.open(recordingID: recording.id)
        await reopened.waitUntilSettled()

        #expect(reopened.lines.count == 3)
    }

    // MARK: - Synchronizing

    @Test func playbackHighlightsTheLineBeingSpoken() async throws {
        _ = try await transcribedAndOpened()
        #expect(viewModel.activeLineIndex == 0)

        playback.emit(.timeChanged(5.5))
        #expect(viewModel.activeLineIndex == 1)

        playback.emit(.timeChanged(19))
        #expect(viewModel.activeLineIndex == 1)

        playback.emit(.timeChanged(21))
        #expect(viewModel.activeLineIndex == 2)
    }

    @Test func theHighlightOnlyChangesWhenTheLineDoes() async throws {
        _ = try await transcribedAndOpened()
        var changes = 0
        func observe() {
            withObservationTracking {
                _ = viewModel.activeLineIndex
            } onChange: {
                MainActor.assumeIsolated { changes += 1 }
            }
        }
        observe()

        for tenth in 1..<40 {
            playback.emit(.timeChanged(Double(tenth) / 10))
        }
        #expect(changes == 0)

        playback.emit(.timeChanged(6))
        #expect(changes == 1)
    }

    @Test func selectingALineSeeksToItsStart() async throws {
        _ = try await transcribedAndOpened()

        viewModel.seekToLine(at: 2)
        await viewModel.waitUntilSettled()

        #expect(playback.seeks == [.seek(20, .exact)])
        #expect(viewModel.position == 20)
        #expect(viewModel.activeLineIndex == 2)
    }

    @Test func scrollingByHandStopsFollowingUntilAskedToResume() async throws {
        _ = try await transcribedAndOpened()
        #expect(viewModel.isFollowingPlayback)

        viewModel.pauseFollowingPlayback()
        playback.emit(.timeChanged(6))
        #expect(!viewModel.isFollowingPlayback)
        #expect(viewModel.activeLineIndex == 1)

        viewModel.resumeFollowingPlayback()
        #expect(viewModel.isFollowingPlayback)
    }

    @Test func searchFindsLinesInARealTranscript() async throws {
        _ = try await transcribedAndOpened()

        viewModel.updateSearchText("words")

        #expect(viewModel.matchingLineIndices == [0, 1])
        viewModel.showNextMatch()
        #expect(viewModel.currentMatchLineIndex == 1)
    }

    // MARK: - Getting it out

    @Test func exportsAreRenderedFromTheStoredTranscript() async throws {
        _ = try await transcribedAndOpened()

        viewModel.requestExport(.srt)
        let document = try #require(viewModel.exportDocument)

        let text = try #require(String(bytes: document.data, encoding: .utf8))
        #expect(text.contains("00:00:05,000 --> 00:00:09,000"))
        viewModel.finishExport(.success(URL(filePath: "/tmp/x.srt")))
        #expect(viewModel.exportRequest == nil)
    }

    @Test func aFilesWarningIsShownWhenTheFilesCouldNotBeWritten() async throws {
        let unwritable = try ProcessingTestEnvironment(files: ConfigurableFileStore(writeError: TestError.failed))
        await unwritable.coordinator.start()
        let viewer = ViewerViewModel(
            library: unwritable.service,
            playback: playback,
            processing: unwritable.coordinator
        )
        let recording = try await unwritable.addRecording()
        unwritable.coordinator.enqueue(recording.id)
        await unwritable.coordinator.waitUntilSettled()

        viewer.open(recordingID: recording.id)
        await viewer.waitUntilSettled()

        #expect(viewer.transcriptExportWarning != nil)
        #expect(viewer.recording?.hasTranscript == true)
    }

    @Test func aMissingFileOffersNothingToStart() async throws {
        let recording = try await environment.addRecording()
        try FileManager.default.removeItem(at: recording.media.url)

        viewModel.open(recordingID: recording.id)
        await viewModel.waitUntilSettled()

        #expect(viewModel.transcriptionActionTitle == nil)
    }
}

@MainActor
struct LibraryProcessingTests {
    let environment: ProcessingTestEnvironment
    let viewModel: LibraryViewModel

    init() async throws {
        environment = try ProcessingTestEnvironment()
        await environment.coordinator.start()
        viewModel = LibraryViewModel(service: environment.service, processing: environment.coordinator)
    }

    private func status(of id: UUID) async -> LibraryItem.Status? {
        await viewModel.reload()
        return viewModel.visibleItems.first { $0.id == id }?.status
    }

    @Test func statusFollowsTheJobFromNotTranscribedToReady() async throws {
        let recording = try await environment.addRecording()
        #expect(await status(of: recording.id) == .recorded)
        #expect(viewModel.item(withID: recording.id)?.statusActionTitle == String(localized: "Transcribe"))

        environment.coordinator.setRecordingActive(true)
        viewModel.startProcessing(recording.id)
        #expect(await status(of: recording.id) == .pending)

        environment.transcription.update { $0.holdsCalls = true }
        environment.coordinator.setRecordingActive(false)
        try await environment.waitUntilHeld()
        try await environment.wait { environment.coordinator.progress[recording.id] == 0.25 }
        #expect(await status(of: recording.id) == .transcribing(progress: 0.25))

        environment.transcription.releaseCalls()
        await environment.coordinator.waitUntilSettled()
        #expect(await status(of: recording.id) == .ready)
        #expect(viewModel.item(withID: recording.id)?.hasTranscript == true)
        #expect(viewModel.item(withID: recording.id)?.canRetranscribe == true)
    }

    @Test func aFailureOffersRetryAndExplainsItself() async throws {
        let recording = try await environment.addRecording()
        environment.models.failure = .noModelSelected
        viewModel.startProcessing(recording.id)
        await environment.coordinator.waitUntilSettled()

        #expect(await status(of: recording.id) == .failed)
        let item = try #require(viewModel.item(withID: recording.id))
        #expect(item.canStartProcessing)
        #expect(item.statusActionTitle == String(localized: "Retry"))
        #expect(item.failureIssue?.recovery == .openSettings)
    }

    @Test func aChangeReloadsTheListWithoutARestart() async throws {
        let recording = try await environment.addRecording()
        let before = viewModel.reloadKey

        viewModel.startProcessing(recording.id)
        await environment.coordinator.waitUntilSettled()

        #expect(viewModel.reloadKey != before)
    }

    @Test func theProcessingSectionListsQueuedAndFailedRecordings() async throws {
        let queued = try await environment.addRecording(title: "Queued")
        let failed = try await environment.addRecording(title: "Failed")
        _ = try await environment.addRecording(title: "Untouched")
        environment.models.failure = .noModelSelected
        viewModel.startProcessing(failed.id)
        await environment.coordinator.waitUntilSettled()
        environment.coordinator.setRecordingActive(true)
        viewModel.startProcessing(queued.id)
        await environment.coordinator.waitUntilSettled()
        try await environment.wait { environment.coordinator.revision > 0 }
        await environment.coordinator.waitUntilSettled()

        viewModel.filter = .processing
        await viewModel.reload()

        #expect(Set(viewModel.visibleItems.map(\.title)) == ["Queued", "Failed"])
        #expect(viewModel.count(for: .processing) == 2)
    }

    @Test func actionsFollowTheState() async throws {
        let recording = try await environment.addRecording()
        await viewModel.reload()
        var item = try #require(viewModel.item(withID: recording.id))
        #expect(LibraryContextMenu.Command.transcription.isEnabled(for: item))
        #expect(!LibraryContextMenu.Command.openTranscript.isEnabled(for: item))

        environment.transcription.update { $0.holdsCalls = true }
        viewModel.startProcessing(recording.id)
        try await environment.waitUntilHeld()
        await viewModel.reload()
        item = try #require(viewModel.item(withID: recording.id))
        #expect(item.isProcessing)
        #expect(LibraryContextMenu.Command.transcription.isEnabled(for: item))

        viewModel.cancelProcessing(recording.id)
        await environment.coordinator.waitUntilSettled()
        #expect(await status(of: recording.id) == .recorded)
    }
}
