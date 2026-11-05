import Foundation

/// What to transcribe, and with what. The caller has already resolved the model and holds its lease.
struct TranscriptionRequest: Sendable {
    let recordingID: UUID
    /// Kept reachable by the caller until the call returns.
    let mediaURL: URL
    let model: ResolvedSpeechModel
    let language: TranscriptionLanguage
}

/// What a recognizer heard, not yet checked or ordered: `Transcript.assembled` does that.
struct TranscriptionOutput: Sendable {
    let speech: [RecognizedSpeech]
    /// The language heard most, or the one asked for. `nil` when no speech was found.
    let language: String?
    /// `nil` when the model does not report one.
    let modelVersion: String?
    /// The length of the media, which speech times must stay within.
    let mediaDuration: TimeInterval
}

/// Offline speech recognition of local media. Never downloads anything.
protocol TranscriptionService: Sendable {
    /// Throws `TranscriptionFailure`, or `CancellationError` once cancelled. Cancellation takes effect at the
    /// recognizer's next checkpoint, which can be a moment away: a running Core ML prediction cannot be interrupted.
    func transcribe(
        _ request: TranscriptionRequest,
        onUpdate: @escaping @Sendable (TranscriptionUpdate) -> Void
    ) async throws -> TranscriptionOutput
    /// Frees whatever the model holds in memory. Safe to call with nothing loaded.
    func releaseModel() async
}

/// Stores finished transcripts. Throws `LibraryError`.
protocol TranscriptRepository: Sendable {
    func transcript(for recordingID: UUID) async throws -> Transcript?
    /// Swaps in a complete transcript in one transaction: on failure, the previous one is still there, whole. Throws
    /// `LibraryError.recordingNotFound` when the recording has left the Library.
    func replaceTranscript(_ transcript: Transcript) async throws
    func deleteTranscript(for recordingID: UUID) async throws
}

/// Stores the job queue. Throws `LibraryError`.
protocol ProcessingJobRepository: Sendable {
    func allJobs() async throws -> [TranscriptionJob]
    /// Stores the job and, in the same transaction, the status the Library's queries use.
    func saveJob(_ job: TranscriptionJob) async throws
    func deleteJob(for recordingID: UUID) async throws
    /// Forgets jobs and transcripts of recordings no longer in the Library. They stay until now so that undoing a
    /// removal brings a recording's transcript back with it.
    func purgeOrphans() async throws
}

/// The transcript files kept beside a recording's media.
protocol TranscriptFileStore: Sendable {
    /// Replaces each file atomically. Throws when a file cannot be written; the media is never involved.
    func writeFiles(of transcript: Transcript, besideMediaAt mediaURL: URL) async throws
    /// `nil` when the volume does not say.
    func availableBytes(besideMediaAt mediaURL: URL) async -> Int64?
}

/// Where transcription gets its model. Implemented by `ModelManager`, the only owner of model state.
@MainActor
protocol TranscriptionModelSource: AnyObject {
    /// Brings model state in line with the disk, so files removed since launch are noticed before they are needed.
    func prepareForUse() async
    /// Throws `ModelManagementError`; the caller reports it rather than choosing another model.
    func acquireSelectedModel() throws(ModelManagementError) -> ModelLease
    func release(_ lease: ModelLease)
}

/// Takes in recordings that should be transcribed now that their media is safe.
@MainActor
protocol TranscriptionScheduling: AnyObject {
    func enqueueTranscription(of recordingID: UUID)
}

/// Told when a recording leaves the Library.
@MainActor
protocol RecordingRemovalObserving: AnyObject {
    /// `permanently` is false when the removal can still be undone.
    func recordingRemoved(_ recordingID: UUID, permanently: Bool)
}
