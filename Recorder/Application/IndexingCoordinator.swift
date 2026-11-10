import Foundation
import Observation
import os

/// The single owner of search indexing: a queue that indexes one recording at a time and outlives every window.
///
/// Indexing is the last step after a recording: it waits while transcription or a summary is queued or running, so it
/// runs once both are done and two models are never loaded for post-processing at once. Chunks and their full-text
/// index need no model; vectors are made when an embedding model is selected and ready, and recordings indexed before
/// that are given vectors once it is.
///
/// Jobs are kept in memory only. The index records which transcript and summary it was made from and which chunks have
/// vectors, so at launch, and whenever the model changes, whatever is missing or out of date is queued again. Recording
/// comes first: `setRecordingActive(true)` stops the running job without waiting, and it continues afterwards from the
/// vectors already stored.
@MainActor
@Observable
final class IndexingCoordinator {
    struct Dependencies {
        let transcripts: any TranscriptRepository
        let summaries: any SummaryRepository
        let index: any SearchIndexRepository
        let embeddings: any EmbeddingProvider
        /// Whether transcription or summaries have work queued or running. Read under observation, so a change starts
        /// the queue.
        let isPostProcessingBusy: @MainActor () -> Bool
        var now: @Sendable () -> Date = { .now }
    }

    /// Why the running job is being stopped, which decides where it goes next.
    enum StopReason {
        case recordingPriority
        case removed
    }

    struct ActiveJob {
        let recordingID: UUID
        var task: Task<Void, Never>?
        var stopReason: StopReason?
    }

    /// Queued, running and failed jobs, by recording. A finished one leaves only the index.
    private(set) var jobs: [UUID: IndexingJob] = [:]
    /// Advances once a recording's index has changed, so whatever searches it can search again.
    private(set) var revision = 0
    private(set) var isRecordingActive = false

    @ObservationIgnored let dependencies: Dependencies
    @ObservationIgnored var active: ActiveJob?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var observedSpace: EmbeddingSpace?
    /// Recordings asked for again while their job was running.
    @ObservationIgnored private var pendingRerun: Set<UUID> = []
    @ObservationIgnored private var catchUp: Task<Void, Never>?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func job(for recordingID: UUID) -> IndexingJob? {
        jobs[recordingID]
    }

    /// Something is queued or running.
    var hasActiveJobs: Bool {
        jobs.values.contains { $0.state.isActive }
    }

    // MARK: - Lifecycle

    /// Forgets the index of recordings removed in an earlier session, then queues whatever is missing or out of date.
    /// Loads no model by itself; the first job that needs vectors does.
    func start() async {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        do {
            try await dependencies.index.purgeOrphans()
        } catch {
            Self.logger.error("Could not clear the index of removed recordings: \(String(describing: error))")
        }
        await dependencies.embeddings.prepareForUse()
        observeReadySpace()
        await queueOutdatedRecordings()
    }

    /// Waits until nothing is running, for callers that need the outcome.
    func waitUntilSettled() async {
        await catchUp?.value
        while let task = active?.task {
            await task.value
        }
    }

    // MARK: - Requests

    /// Queues the recording, to bring its index up to date with its transcript and summary. Ignored while one is
    /// queued, which reads them when it starts. A running job may have read them already, so it runs once more.
    func enqueue(_ recordingID: UUID) {
        if active?.recordingID == recordingID {
            pendingRerun.insert(recordingID)
            return
        }
        if let current = jobs[recordingID], current.state.isActive {
            return
        }
        jobs[recordingID] = IndexingJob(recordingID: recordingID, state: .queued, queuedAt: dependencies.now())
        startNextJob()
    }

    /// Forgets a failure once it has been seen.
    func dismissFailure(of recordingID: UUID) {
        if case .failed = jobs[recordingID]?.state {
            jobs[recordingID] = nil
        }
    }

    /// Recording takes priority, from when one starts preparing until its media is safe. Never waits for the model.
    func setRecordingActive(_ isActive: Bool) {
        guard isActive != isRecordingActive else {
            return
        }
        isRecordingActive = isActive
        dependencies.embeddings.setRecordingActive(isActive)
        if isActive {
            stopActiveJob(.recordingPriority)
        } else {
            startNextJob()
        }
    }

    // MARK: - Queue

    func startNextJob() {
        guard !isRecordingActive, active == nil, let next = nextQueuedJob(), !postProcessingHoldsQueue() else {
            return
        }
        let recordingID = next.recordingID
        active = ActiveJob(recordingID: recordingID)
        setState(.chunking, of: recordingID)
        active?.task = Task { [weak self] in
            await self?.run(recordingID)
        }
    }

    /// A job asked for again while it ran is queued once more, unless it failed or went back to the queue anyway.
    func finishActiveJob() {
        if let recordingID = active?.recordingID, pendingRerun.remove(recordingID) != nil, jobs[recordingID] == nil {
            jobs[recordingID] = IndexingJob(recordingID: recordingID, state: .queued, queuedAt: dependencies.now())
        }
        active = nil
        startNextJob()
    }

    private func nextQueuedJob() -> IndexingJob? {
        jobs.values
            .filter { $0.state == .queued }
            .min { ($0.queuedAt, $0.recordingID.uuidString) < ($1.queuedAt, $1.recordingID.uuidString) }
    }

    /// Reads the other queues' state under observation, so indexing starts by itself once they are done.
    private func postProcessingHoldsQueue() -> Bool {
        withObservationTracking {
            dependencies.isPostProcessingBusy()
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

    func setState(_ state: IndexingJob.State, of recordingID: UUID) {
        jobs[recordingID]?.state = state
    }

    func removeJob(_ recordingID: UUID) {
        jobs[recordingID] = nil
    }

    func completed(_ recordingID: UUID) {
        jobs[recordingID] = nil
        revision += 1
    }

    // MARK: - Catching up

    /// Watches which model is ready, so selecting or installing one gives vectors to everything indexed without it.
    private func observeReadySpace() {
        let space = withObservationTracking {
            dependencies.embeddings.readySpace
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.readySpaceChanged()
            }
        }
        observedSpace = space
    }

    private func readySpaceChanged() {
        let previous = observedSpace
        observeReadySpace()
        guard observedSpace != nil, observedSpace != previous else {
            return
        }
        catchUp = Task { [weak self] in
            await self?.queueOutdatedRecordings()
        }
    }

    /// Queues recordings whose chunks are out of date, and those without vectors in the ready model's space. Vectors of
    /// other models are forgotten, since nothing searches them.
    private func queueOutdatedRecordings() async {
        let index = dependencies.index
        var recordingIDs: [UUID] = []
        do {
            recordingIDs = try await index.recordingsWithOutdatedChunks()
            if let space = dependencies.embeddings.readySpace {
                try await index.removeEmbeddings(outside: space)
                recordingIDs += try await index.recordingsWithPendingEmbeddings(in: space)
            }
        } catch {
            Self.logger.error("Could not find recordings to index: \(String(describing: error))")
        }
        var seen: Set<UUID> = []
        for recordingID in recordingIDs where seen.insert(recordingID).inserted {
            enqueue(recordingID)
        }
        if !seen.isEmpty {
            Self.logger.info("Queued \(seen.count) recordings for indexing")
        }
    }

    static let logger = Logger(subsystem: "dev.local.Recorder", category: "Search")
}

extension IndexingCoordinator: RecordingRemovalObserving {
    /// The job goes with the recording. The index stays while a removal can be undone, and until the next launch.
    func recordingRemoved(_ recordingID: UUID, permanently: Bool) {
        if active?.recordingID == recordingID {
            stopActiveJob(.removed)
        }
        jobs[recordingID] = nil
        pendingRerun.remove(recordingID)
        guard permanently else {
            return
        }
        let index = dependencies.index
        Task {
            do {
                try await index.deleteIndex(for: recordingID)
            } catch {
                Self.logger.error("Could not delete a recording's index: \(String(describing: error))")
            }
        }
    }
}
