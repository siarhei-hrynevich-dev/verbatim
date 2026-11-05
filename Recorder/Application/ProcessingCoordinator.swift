import Foundation
import Observation
import os

/// The single owner of transcription work: a small durable queue that runs one job at a time and outlives every window.
///
/// State changes happen synchronously on the main actor before any suspension, so a duplicate request is rejected by
/// the state check. Inference runs off the main actor in `TranscriptionService`.
///
/// Recording always comes first. `setRecordingActive(true)` stops the running job and holds the rest back without ever
/// waiting for inference, so it cannot delay capture; the job goes back to the queue and restarts from the beginning
/// when the recording ends. Interrupted jobs recover the same way after a restart.
@MainActor
@Observable
final class ProcessingCoordinator {
    struct Dependencies {
        let jobs: any ProcessingJobRepository
        let transcripts: any TranscriptRepository
        let transcription: any TranscriptionService
        let models: any TranscriptionModelSource
        let library: LibraryService
        let files: any TranscriptFileStore
        /// The language Settings asks for right now, read when a job starts.
        let language: @MainActor () -> TranscriptionLanguage
        var now: @Sendable () -> Date = { .now }
    }

    /// Why the running job is being stopped, which decides where it goes next.
    enum StopReason {
        case cancelled
        case recordingPriority
        case removed
    }

    struct ActiveJob {
        let recordingID: UUID
        var task: Task<Void, Never>?
        var stopReason: StopReason?
    }

    /// Every known job, by recording.
    private(set) var jobs: [UUID: TranscriptionJob] = [:]
    /// The measured progress of the running job, from 0 to 1. Absent until there is something to measure.
    private(set) var progress: [UUID: Double] = [:]
    /// Advances once a job's change has been stored, so whatever reads the database then sees it.
    private(set) var revision = 0
    private(set) var isRecordingActive = false
    /// The running job has been asked to stop, and may take a moment to reach a point where it can.
    private(set) var stoppingRecordingID: UUID?

    @ObservationIgnored let dependencies: Dependencies
    @ObservationIgnored var active: ActiveJob?
    @ObservationIgnored private var hasLoaded = false
    /// Keeps stored changes in the order they were made.
    @ObservationIgnored private var lastStore: Task<Void, Never>?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    // MARK: - Reading

    func job(for recordingID: UUID) -> TranscriptionJob? {
        jobs[recordingID]
    }

    func isStopping(_ recordingID: UUID) -> Bool {
        stoppingRecordingID == recordingID
    }

    func transcript(for recordingID: UUID) async throws -> Transcript? {
        try await dependencies.transcripts.transcript(for: recordingID)
    }

    // MARK: - Lifecycle

    /// Loads the queue and resumes it. A job that was running when the app last ended restarts from the beginning: a
    /// transcript is only ever stored whole, so nothing it did needs undoing. Loads no model by itself.
    func start() async {
        guard !hasLoaded else {
            return
        }
        do {
            try await dependencies.jobs.purgeOrphans()
            for var job in try await dependencies.jobs.allJobs() where jobs[job.recordingID] == nil {
                let wasInterrupted = job.state.isActive && job.state != .pending
                if wasInterrupted {
                    job.state = .pending
                    Self.logger.notice("Restarting a job interrupted by the app ending")
                }
                jobs[job.recordingID] = job
                if wasInterrupted {
                    store(job)
                }
            }
        } catch {
            Self.logger.error("Could not load the transcription queue: \(String(describing: error))")
        }
        hasLoaded = true
        startNextJob()
    }

    /// Waits until nothing is running and everything is stored, for callers that need the outcome.
    func waitUntilSettled() async {
        while let task = active?.task {
            await task.value
        }
        await lastStore?.value
    }

    // MARK: - Requests

    /// Queues the recording, for a first transcript, a retry or a re-transcription alike. Ignored while one is queued
    /// or running. Any existing transcript stays in place until its replacement is complete.
    func enqueue(_ recordingID: UUID) {
        if let current = jobs[recordingID], current.state.isActive {
            Self.logger.notice("Ignored a request for a recording already being transcribed")
            return
        }
        let now = dependencies.now()
        var job =
            jobs[recordingID]
            ?? TranscriptionJob(recordingID: recordingID, state: .pending, queuedAt: now, updatedAt: now)
        job.state = .pending
        job.queuedAt = now
        job.updatedAt = now
        job.failure = nil
        job.exportFailureDetail = nil
        jobs[recordingID] = job
        store(job)
        startNextJob()
    }

    /// Stops the job. A queued one stops at once; a running one at its next checkpoint, leaving nothing behind.
    func cancel(_ recordingID: UUID) {
        guard let job = jobs[recordingID], job.state.isActive else {
            return
        }
        if active?.recordingID == recordingID {
            stopActiveJob(.cancelled)
        } else {
            setState(.cancelled, of: recordingID)
        }
    }

    /// Recording takes priority, from when one starts preparing until its media is safe. Never waits for inference.
    func setRecordingActive(_ isActive: Bool) {
        guard isActive != isRecordingActive else {
            return
        }
        isRecordingActive = isActive
        if isActive {
            stopActiveJob(.recordingPriority)
        } else {
            startNextJob()
        }
    }

    // MARK: - Queue

    func finishActiveJob() {
        active = nil
        stoppingRecordingID = nil
        startNextJob()
    }

    private func startNextJob() {
        guard hasLoaded, !isRecordingActive, active == nil, let next = nextPendingJob() else {
            return
        }
        active = ActiveJob(recordingID: next.recordingID)
        var job = next
        job.attempts += 1
        jobs[next.recordingID] = job
        setState(.preparing, of: next.recordingID)
        active?.task = Task { [weak self] in
            await self?.run(next.recordingID)
        }
    }

    func nextPendingJob() -> TranscriptionJob? {
        jobs.values
            .filter { $0.state == .pending }
            .min { ($0.queuedAt, $0.recordingID.uuidString) < ($1.queuedAt, $1.recordingID.uuidString) }
    }

    private func stopActiveJob(_ reason: StopReason) {
        guard active != nil, active?.stopReason == nil else {
            return
        }
        active?.stopReason = reason
        stoppingRecordingID = active?.recordingID
        active?.task?.cancel()
    }

    // MARK: - Changing jobs

    func setState(_ next: TranscriptionJob.State, of recordingID: UUID) {
        guard var job = jobs[recordingID] else {
            return
        }
        guard job.state.allowsTransition(to: next) else {
            assertionFailure("Invalid transcription transition from \(job.state) to \(next)")
            Self.logger.fault("Invalid transcription transition from \(job.state.rawValue, privacy: .public)")
            return
        }
        job.state = next
        job.updatedAt = dependencies.now()
        if !next.isActive || next == .pending {
            progress[recordingID] = nil
        }
        jobs[recordingID] = job
        store(job)
    }

    func update(_ recordingID: UUID, _ change: (inout TranscriptionJob) -> Void) {
        guard var job = jobs[recordingID] else {
            return
        }
        change(&job)
        job.updatedAt = dependencies.now()
        jobs[recordingID] = job
        store(job)
    }

    func setProgress(_ fraction: Double, of recordingID: UUID) {
        progress[recordingID] = min(max(fraction, 0), 1)
    }

    func removeJob(_ recordingID: UUID) {
        jobs[recordingID] = nil
        progress[recordingID] = nil
        enqueueStore { [jobs = dependencies.jobs] in
            try await jobs.deleteJob(for: recordingID)
        }
    }

    /// A failure to store a job's state costs only what a restart remembers: the job itself carries on.
    private func store(_ job: TranscriptionJob) {
        enqueueStore { [jobs = dependencies.jobs] in
            try await jobs.saveJob(job)
        }
    }

    func enqueueStore(_ operation: @escaping @Sendable () async throws -> Void) {
        let previous = lastStore
        lastStore = Task { [weak self] in
            await previous?.value
            do {
                try await operation()
            } catch {
                Self.logger.error("Could not store a transcription job: \(String(describing: error))")
            }
            self?.revision += 1
        }
    }

    static let logger = Logger(subsystem: "dev.local.Recorder", category: "Transcription")
}

extension ProcessingCoordinator: TranscriptionScheduling {
    func enqueueTranscription(of recordingID: UUID) {
        enqueue(recordingID)
    }
}

extension ProcessingCoordinator: RecordingRemovalObserving {
    /// The job goes with the recording. The transcript stays while a removal can be undone, and until the next launch.
    func recordingRemoved(_ recordingID: UUID, permanently: Bool) {
        if active?.recordingID == recordingID {
            stopActiveJob(.removed)
        }
        removeJob(recordingID)
        guard permanently else {
            return
        }
        enqueueStore { [transcripts = dependencies.transcripts] in
            try await transcripts.deleteTranscript(for: recordingID)
        }
    }
}
