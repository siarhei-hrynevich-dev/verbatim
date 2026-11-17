import Foundation

/// One job's steps. Nothing is reported as done until it is stored, and the only write that matters is a single
/// transaction after inference has finished: a job stopped at any point before it leaves the previous transcript whole.
extension ProcessingCoordinator {
    /// Free space that a job wants beside the media: its transcript files and a margin for the database, which keeps
    /// a nearly full disk from failing halfway through.
    private static let requiredFreeBytes: Int64 = 100_000_000

    func run(_ recordingID: UUID) async {
        do {
            try await performJob(recordingID)
        } catch {
            settle(recordingID, after: error)
        }
        // The next job reuses the loaded model. Otherwise it goes, which a recording in particular wants right away.
        if isRecordingActive || nextPendingJob() == nil {
            await dependencies.transcription.releaseModel()
        }
        finishActiveJob()
    }

    private func performJob(_ recordingID: UUID) async throws {
        await dependencies.models.prepareForUse()
        try Task.checkCancellation()
        let lease = try dependencies.models.acquireSelectedModel()
        defer { dependencies.models.release(lease) }
        update(recordingID) { $0.modelID = lease.model.id }

        let media = try await dependencies.library.openMedia(of: recordingID)
        defer { media.close() }
        try await checkDiskSpace(besideMediaAt: media.url)

        let request = TranscriptionRequest(
            recordingID: recordingID,
            mediaURL: media.url,
            model: lease.model,
            language: dependencies.language()
        )
        let output = try await transcribe(request)
        try Task.checkCancellation()

        setState(.saving, of: recordingID)
        let transcript = Transcript.assembled(
            recordingID: recordingID,
            provenance: Transcript.Provenance(
                modelID: lease.model.id,
                modelVersion: output.modelVersion,
                language: output.language,
                createdAt: dependencies.now()
            ),
            speech: output.speech,
            mediaDuration: output.mediaDuration
        )
        try await dependencies.transcripts.replaceTranscript(transcript)
        await writeFiles(of: transcript, besideMediaAt: media.url)
        setState(.completed, of: recordingID)
        Self.logger.info("Transcribed a recording into \(transcript.segments.count) segments")
        onTranscriptStored?(recordingID)
    }

    private func checkDiskSpace(besideMediaAt mediaURL: URL) async throws {
        let available = await dependencies.files.availableBytes(besideMediaAt: mediaURL)
        if let available, available < Self.requiredFreeBytes {
            throw TranscriptionFailure.insufficientDiskSpace(
                requiredBytes: Self.requiredFreeBytes,
                availableBytes: available
            )
        }
    }

    /// Updates arrive in order through a stream, and only those of the current attempt.
    private func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionOutput {
        let (updates, continuation) = AsyncStream.makeStream(of: TranscriptionUpdate.self)
        let observer = Task { [weak self] in
            for await update in updates {
                self?.apply(update, to: request.recordingID)
            }
        }
        defer {
            continuation.finish()
            observer.cancel()
        }
        let output = try await dependencies.transcription.transcribe(request) { continuation.yield($0) }
        continuation.finish()
        await observer.value
        return output
    }

    private func apply(_ update: TranscriptionUpdate, to recordingID: UUID) {
        guard case .processingAudio(let fraction) = update, active?.recordingID == recordingID else {
            return
        }
        if jobs[recordingID]?.state == .preparing {
            setState(.transcribing, of: recordingID)
        }
        setProgress(fraction, of: recordingID)
    }

    /// The transcript is safe by now, so a file that cannot be written, as beside media reachable only by itself, is
    /// noted rather than failing the job. Files can be regenerated from what is stored.
    private func writeFiles(of transcript: Transcript, besideMediaAt mediaURL: URL) async {
        do {
            try await dependencies.files.writeFiles(of: transcript, besideMediaAt: mediaURL)
        } catch {
            Self.logger.error("Could not write transcript files: \(String(describing: error))")
            update(transcript.recordingID) { $0.exportFailureDetail = error.localizedDescription }
        }
    }

    /// Where a job goes when it did not finish. A stop asked for by someone decides that, whatever the error was.
    private func settle(_ recordingID: UUID, after error: any Error) {
        switch active?.stopReason {
        case .removed:
            return
        case .recordingPriority:
            setState(.pending, of: recordingID)
        case .cancelled:
            setState(.cancelled, of: recordingID)
        case nil:
            if error is CancellationError {
                setState(.cancelled, of: recordingID)
            } else {
                fail(recordingID, with: TranscriptionFailure(error))
            }
        }
    }

    private func fail(_ recordingID: UUID, with failure: TranscriptionFailure) {
        guard failure != .recordingNotFound else {
            removeJob(recordingID)
            return
        }
        Self.logger.error("Transcription failed: \(String(describing: failure), privacy: .public)")
        update(recordingID) { $0.failure = failure }
        setState(.failed, of: recordingID)
    }
}

extension ModelManager: TranscriptionModelSource where Model == SpeechModel {
    func prepareForUse() async {
        await reconcile()
    }
}
