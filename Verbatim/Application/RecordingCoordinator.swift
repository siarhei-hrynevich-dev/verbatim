import Foundation
import Observation
import os

/// The single owner of the recording lifecycle: it validates requests, drives capture and persistence, and keeps
/// running regardless of which windows are open.
///
/// State changes happen synchronously on the main actor before any suspension, so a second request arriving during
/// an `await` is always rejected by the state check rather than racing the first.
@MainActor
@Observable
final class RecordingCoordinator {
    /// The recording in progress, for display.
    struct ActiveRecording: Equatable, Sendable {
        let configuration: RecordingConfiguration
        let sourceName: String
        var isMicrophoneActive: Bool
        var isSystemAudioActive: Bool
    }

    private(set) var state = RecordingState.idle
    private(set) var activeRecording: ActiveRecording?
    private(set) var levels = AudioLevels.silent
    /// The most recent finished recording, until the next start. Set only after finalization.
    private(set) var lastOutcome: RecordingOutcome?

    @ObservationIgnored private let engine: any CaptureEngine
    @ObservationIgnored private let preflight: RecordingPreflight
    @ObservationIgnored private let destinations: any RecordingDestinationStore
    @ObservationIgnored private let metadataStore: any RecordingMetadataStore
    @ObservationIgnored private let library: any FinishedRecordingRegistry
    @ObservationIgnored private let transcriptionScheduler: (any TranscriptionScheduling)?
    @ObservationIgnored private let now: @Sendable () -> Date

    /// The start or stop in progress. Lives as long as the coordinator, independent of any window.
    @ObservationIgnored private var lifecycleTask: Task<Void, Never>?
    /// Delivers session events for the duration of the session.
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    /// Keeps pause and resume in request order.
    @ObservationIgnored private var pauseTask: Task<Void, Never>?
    @ObservationIgnored private var current: CurrentRecording?

    fileprivate struct CurrentRecording {
        let id: UUID
        let createdAt: Date
        let configuration: RecordingConfiguration
        let destination: RecordingDestination
        let session: any CaptureSession
        var interruptions: [RecordingInterruption] = []
    }

    init(
        engine: any CaptureEngine,
        permissions: any CapturePermissions,
        destinations: any RecordingDestinationStore,
        metadataStore: any RecordingMetadataStore,
        library: any FinishedRecordingRegistry,
        transcriptionScheduler: (any TranscriptionScheduling)? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.engine = engine
        preflight = RecordingPreflight(permissions: permissions, destinations: destinations)
        self.destinations = destinations
        self.metadataStore = metadataStore
        self.library = library
        self.transcriptionScheduler = transcriptionScheduler
        self.now = now
    }

    // MARK: - Requests

    /// Ignored unless idle or failed, which is what prevents duplicate starts.
    func requestStart(_ configuration: RecordingConfiguration) {
        guard state.acceptsStart else {
            Self.logger.notice("Ignored a start request during an active lifecycle")
            return
        }
        lastOutcome = nil
        transition(to: .preparing)
        lifecycleTask = Task {
            await performStart(configuration)
        }
    }

    /// Ignored unless recording.
    func requestStop() {
        stop(interruption: nil)
    }

    func togglePause() {
        guard case .recording(var clock) = state, let session = current?.session else {
            return
        }
        let shouldPause = !clock.isPaused
        if shouldPause {
            clock.pause(at: now())
        } else {
            clock.resume(at: now())
        }
        transition(to: .recording(clock))
        let previous = pauseTask
        pauseTask = Task {
            await previous?.value
            if shouldPause {
                await session.pause()
            } else {
                await session.resume()
            }
        }
    }

    /// Clears a shown failure, returning to idle.
    func acknowledgeFailure() {
        guard case .failed = state else {
            return
        }
        transition(to: .idle)
    }

    func acknowledgeOutcome() {
        lastOutcome = nil
    }

    /// Waits for any start or stop in progress.
    func waitUntilSettled() async {
        await lifecycleTask?.value
    }

    /// Ends any recording and waits until its media is safe, for quitting.
    func stopAndWait() async {
        await waitUntilSettled()
        requestStop()
        await waitUntilSettled()
    }

    // MARK: - Starting

    private func performStart(_ configuration: RecordingConfiguration) async {
        do {
            try await preflight.check(configuration)

            let id = UUID()
            let createdAt = now()
            let destination = try await destinations.prepareDestination(id: id, createdAt: createdAt)
            let session = try await startSession(configuration, destination: destination)
            current = CurrentRecording(
                id: id,
                createdAt: createdAt,
                configuration: configuration,
                destination: destination,
                session: session
            )
            activeRecording = ActiveRecording(
                configuration: configuration,
                sourceName: configuration.sourceName,
                isMicrophoneActive: configuration.microphone != nil,
                isSystemAudioActive: configuration.capturesSystemAudio
            )
            observeEvents(of: session)
            transition(to: .recording(RecordingClock(startedAt: now())))
        } catch {
            transition(to: .failed(Self.startFailure(from: error)))
        }
    }

    private func startSession(
        _ configuration: RecordingConfiguration,
        destination: RecordingDestination
    ) async throws -> any CaptureSession {
        do {
            return try await engine.startSession(configuration: configuration, outputURL: destination.mediaURL)
        } catch {
            _ = await destinations.discardIfEmpty(destination)
            throw error
        }
    }

    private func observeEvents(of session: any CaptureSession) {
        eventsTask = Task { [weak self] in
            for await event in session.events {
                self?.handle(event)
            }
        }
    }

    // MARK: - Stopping

    fileprivate func stop(interruption: RecordingInterruption?) {
        guard case .recording(var clock) = state, var recording = current else {
            return
        }
        if let interruption {
            recording.interruptions.append(interruption)
        }
        clock.pause(at: now())
        transition(to: .stopping(clock))
        let pauseTask = pauseTask
        lifecycleTask = Task {
            await pauseTask?.value
            await performStop(recording, clock: clock)
        }
    }

    private func performStop(_ recording: CurrentRecording, clock: RecordingClock) async {
        await recording.session.stopCapture()
        transition(to: .finalizing(clock))
        do {
            let media = try await recording.session.finalize()
            lastOutcome = await saveCompleted(recording, media: media)
            finishLifecycle(with: .idle)
        } catch {
            let failure = await finalizationFailure(from: error, recording: recording, clock: clock)
            finishLifecycle(with: .failed(failure))
        }
    }

    private func finishLifecycle(with finalState: RecordingState) {
        eventsTask?.cancel()
        eventsTask = nil
        pauseTask = nil
        current = nil
        activeRecording = nil
        levels = .silent
        transition(to: finalState)
    }

    // MARK: - Helpers

    private func transition(to next: RecordingState) {
        guard state.allowsTransition(to: next) else {
            assertionFailure("Invalid recording transition from \(state) to \(next)")
            Self.logger.fault("Invalid recording transition from \(String(describing: self.state))")
            return
        }
        state = next
    }

    private static func startFailure(from error: any Error) -> RecordingFailure {
        if let failure = error as? RecordingFailure {
            return failure
        }
        logger.error("Could not start recording: \(String(describing: error))")
        return .initializationFailed(detail: error.localizedDescription)
    }

    private static let logger = Logger(category: "Recording")
}

// MARK: - Saving

extension RecordingCoordinator {
    /// The media is already safe here, so a failure to store its details is reported without touching it. The sidecar
    /// and the Library are independent: one failing does not stop the other.
    private func saveCompleted(_ recording: CurrentRecording, media: CapturedMedia) async -> RecordingOutcome {
        var metadataErrorDetail: String?
        let metadata = recording.metadata(media: media, completion: .complete)
        do {
            try await metadataStore.save(metadata, in: recording.destination)
        } catch {
            Self.logger.error("Could not save recording metadata: \(String(describing: error))")
            metadataErrorDetail = error.localizedDescription
        }
        do {
            try await library.addFinishedRecording(metadata, destination: recording.destination)
            // The media is safe and has an entry. The job waits its turn until this recording has fully ended.
            if metadata.transcriptionRequested, !media.audioSources.isEmpty {
                transcriptionScheduler?.enqueueTranscription(of: recording.id)
            }
        } catch {
            Self.logger.error("Could not add a recording to the Library: \(String(describing: error))")
            metadataErrorDetail = metadataErrorDetail ?? error.localizedDescription
        }
        return RecordingOutcome(
            metadata: metadata,
            destination: recording.destination,
            interruptions: recording.interruptions,
            metadataErrorDetail: metadataErrorDetail
        )
    }

    private func finalizationFailure(
        from error: any Error,
        recording: CurrentRecording,
        clock: RecordingClock
    ) async -> RecordingFailure {
        Self.logger.error("Could not finalize a recording: \(String(describing: error))")
        let isDiscarded = await destinations.discardIfEmpty(recording.destination)
        if !isDiscarded {
            await saveIncompleteMetadata(recording, clock: clock)
        }
        if let failure = error as? RecordingFailure {
            return failure
        }
        return .finalizationFailed(
            detail: error.localizedDescription,
            directoryPath: recording.destination.directoryURL.path(percentEncoded: false)
        )
    }

    /// Records what is known about an unfinished recording so it can be found and recovered later.
    private func saveIncompleteMetadata(_ recording: CurrentRecording, clock: RecordingClock) async {
        let media = CapturedMedia(
            duration: clock.elapsed(at: now()),
            fileSizeBytes: 0,
            hasVideo: recording.configuration.capturesVideo,
            audioSources: recording.configuration.audioSources
        )
        do {
            try await metadataStore.save(
                recording.metadata(media: media, completion: .incomplete),
                in: recording.destination
            )
        } catch {
            Self.logger.error("Could not save metadata for an incomplete recording: \(String(describing: error))")
        }
    }
}

// MARK: - Session events

extension RecordingCoordinator {
    private func handle(_ event: CaptureEvent) {
        switch event {
        case .levels(let levels):
            self.levels = levels
        case .videoSourceLost:
            stop(interruption: .sourceLost(name: current?.configuration.sourceName ?? ""))
        case .microphoneLost:
            activeRecording?.isMicrophoneActive = false
            let name = current?.configuration.microphone?.name ?? ""
            sourceWasLost(.microphoneLost(name: name))
        case .systemAudioLost(let detail):
            activeRecording?.isSystemAudioActive = false
            sourceWasLost(.systemAudioLost(detail: detail))
        case .writeFailed(let detail):
            stop(interruption: .writeFailed(detail: detail))
        }
    }

    /// Recording carries on with its remaining sources, and ends only when none remain.
    private func sourceWasLost(_ interruption: RecordingInterruption) {
        guard let activeRecording, state.acceptsStop else {
            return
        }
        let hasRemainingSource =
            activeRecording.configuration.capturesVideo
            || activeRecording.isMicrophoneActive
            || activeRecording.isSystemAudioActive
        if hasRemainingSource {
            current?.interruptions.append(interruption)
        } else {
            stop(interruption: interruption)
        }
    }
}

extension RecordingCoordinator.CurrentRecording {
    fileprivate func metadata(
        media: CapturedMedia,
        completion: RecordingMetadata.Completion
    ) -> RecordingMetadata {
        RecordingMetadata(
            recording: Recording(
                id: id,
                createdAt: createdAt,
                validatedMediaDuration: media.duration,
                processingStatus: .recorded
            ),
            mediaFileName: destination.mediaURL.lastPathComponent,
            captureMode: configuration.target?.mode ?? .audioOnly,
            sourceName: configuration.sourceName,
            hasVideo: media.hasVideo,
            audioSources: media.audioSources,
            fileSizeBytes: media.fileSizeBytes,
            completion: completion,
            transcriptionRequested: configuration.transcribesWhenFinished
        )
    }
}
