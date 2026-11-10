import Foundation
import Observation
import os

/// The single owner of summary work: a queue that runs one summary at a time and outlives every window.
///
/// State changes happen synchronously on the main actor before any suspension, so a duplicate request is rejected by
/// the state check. Generation runs off the main actor in the `TextGenerator`.
///
/// Recording comes first, as for transcription: `setRecordingActive(true)` stops the running summary without waiting,
/// and it starts over when the recording ends. Summaries also wait while transcription is queued or running, so two
/// models are never loaded for post-processing at once. Jobs are kept in memory only: the summary is the durable
/// result, and one interrupted by quitting is asked for again.
@MainActor
@Observable
final class SummaryCoordinator {
    struct Dependencies {
        let transcripts: any TranscriptRepository
        let summaries: any SummaryRepository
        let generation: any TextGenerationProvider
        /// Whether transcription has work queued or running. Read under observation, so a change starts the queue.
        let isTranscriptionBusy: @MainActor () -> Bool
        /// The language Settings asks for right now, read when a summary starts.
        let language: @MainActor () -> SummaryLanguage
        var now: @Sendable () -> Date = { .now }
    }

    /// Why the running summary is being stopped, which decides where it goes next.
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

    /// Queued, running and failed summaries, by recording. A finished one leaves only its stored summary.
    private(set) var jobs: [UUID: SummaryJob] = [:]
    /// Advances once a summary has been stored, so whatever shows it reads it again.
    private(set) var revision = 0
    private(set) var isRecordingActive = false

    /// Told once a summary has been stored, for work that follows it, such as indexing.
    @ObservationIgnored var onSummaryStored: (@MainActor (UUID) -> Void)?
    @ObservationIgnored let dependencies: Dependencies
    @ObservationIgnored var active: ActiveJob?
    @ObservationIgnored private var hasStarted = false

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    // MARK: - Reading

    /// What new summaries are written in.
    var language: SummaryLanguage {
        dependencies.language()
    }

    func job(for recordingID: UUID) -> SummaryJob? {
        jobs[recordingID]
    }

    /// Something is queued or running. Observable, for work that waits until summaries are done.
    var hasActiveJobs: Bool {
        jobs.values.contains { $0.state.isActive }
    }

    func isStopping(_ recordingID: UUID) -> Bool {
        active?.recordingID == recordingID && active?.stopReason != nil
    }

    func summary(for recordingID: UUID) async throws -> TranscriptSummary? {
        try await dependencies.summaries.summary(for: recordingID)
    }

    // MARK: - Lifecycle

    /// Forgets summaries of recordings that left the Library in an earlier session. Loads no model.
    func start() async {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        do {
            try await dependencies.summaries.purgeOrphans()
        } catch {
            Self.logger.error("Could not clear summaries of removed recordings: \(String(describing: error))")
        }
    }

    /// Waits until nothing is running, for callers that need the outcome.
    func waitUntilSettled() async {
        while let task = active?.task {
            await task.value
        }
    }

    // MARK: - Requests

    /// Queues a first summary, a retry or a replacement alike. Ignored while one is queued or running. An existing
    /// summary stays in place until its replacement is complete.
    func enqueue(_ recordingID: UUID) {
        if let current = jobs[recordingID], current.state.isActive {
            Self.logger.notice("Ignored a request for a recording already being summarized")
            return
        }
        jobs[recordingID] = SummaryJob(recordingID: recordingID, state: .queued, queuedAt: dependencies.now())
        startNextJob()
    }

    /// Queues a summary of a transcript that has just been made, when a language model is ready to write it. Without
    /// one nothing happens: summaries are never a reason to download or switch models.
    func enqueueIfModelReady(_ recordingID: UUID) {
        guard dependencies.generation.hasUsableModel else {
            return
        }
        enqueue(recordingID)
    }

    /// Stops the summary. A queued one stops at once; a running one at its next token, leaving nothing behind.
    func cancel(_ recordingID: UUID) {
        guard let job = jobs[recordingID] else {
            return
        }
        if active?.recordingID == recordingID {
            stopActiveJob(.cancelled)
        } else if job.state.isActive {
            jobs[recordingID] = nil
        }
    }

    /// Forgets a failure once it has been seen.
    func dismissFailure(of recordingID: UUID) {
        if case .failed = jobs[recordingID]?.state {
            jobs[recordingID] = nil
        }
    }

    /// Recording takes priority, from when one starts preparing until its media is safe. Never waits for generation.
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

    func startNextJob() {
        guard !isRecordingActive, active == nil, let next = nextQueuedJob(), !transcriptionHoldsQueue() else {
            return
        }
        let recordingID = next.recordingID
        active = ActiveJob(recordingID: recordingID)
        setState(.loadingModel, of: recordingID)
        active?.task = Task { [weak self] in
            await self?.run(recordingID)
        }
    }

    func finishActiveJob() {
        active = nil
        startNextJob()
    }

    private func nextQueuedJob() -> SummaryJob? {
        jobs.values
            .filter { $0.state == .queued }
            .min { ($0.queuedAt, $0.recordingID.uuidString) < ($1.queuedAt, $1.recordingID.uuidString) }
    }

    /// Reads transcription's state under observation, so the queue starts by itself once transcription is done.
    private func transcriptionHoldsQueue() -> Bool {
        withObservationTracking {
            dependencies.isTranscriptionBusy()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.startNextJob()
            }
        }
    }

    private func stopActiveJob(_ reason: StopReason) {
        guard active != nil, active?.stopReason == nil else {
            return
        }
        active?.stopReason = reason
        active?.task?.cancel()
    }

    func setState(_ state: SummaryJob.State, of recordingID: UUID) {
        jobs[recordingID]?.state = state
    }

    func removeJob(_ recordingID: UUID) {
        jobs[recordingID] = nil
    }

    func completed(_ recordingID: UUID) {
        jobs[recordingID] = nil
        revision += 1
        onSummaryStored?(recordingID)
    }

    static let logger = Logger(subsystem: "dev.local.Recorder", category: "Summaries")
}

extension SummaryCoordinator: RecordingRemovalObserving {
    /// The job goes with the recording. The summary stays while a removal can be undone, and until the next launch.
    func recordingRemoved(_ recordingID: UUID, permanently: Bool) {
        if active?.recordingID == recordingID {
            stopActiveJob(.removed)
        }
        jobs[recordingID] = nil
        guard permanently else {
            return
        }
        let summaries = dependencies.summaries
        Task {
            do {
                try await summaries.deleteSummary(for: recordingID)
            } catch {
                Self.logger.error("Could not delete a summary: \(String(describing: error))")
            }
        }
    }
}
