import Foundation

/// One summary's steps. Nothing is stored until the whole summary is written, so a summary stopped at any point leaves
/// the previous one whole.
extension SummaryCoordinator {
    func run(_ recordingID: UUID) async {
        var sessionID: UUID?
        do {
            let transcript = try await readTranscript(of: recordingID)
            await dependencies.generation.prepareForUse()
            try Task.checkCancellation()
            let session = try await dependencies.generation.acquireGenerator()
            sessionID = session.id
            let (summary, title) = try await summarize(transcript, with: session)
            setState(.saving, of: recordingID)
            try await dependencies.summaries.replaceSummary(summary)
            if let title {
                await dependencies.applyGeneratedTitle(recordingID, title)
            }
            completed(recordingID)
            Self.logger.info("Summarized a recording in \(summary.parts.count) parts")
        } catch {
            settle(recordingID, after: error)
        }
        // The generator was local to the steps above, so the model's memory can go now.
        if let sessionID {
            await dependencies.generation.release(sessionID: sessionID)
        }
        finishActiveJob()
    }

    private func readTranscript(of recordingID: UUID) async throws -> Transcript {
        guard let transcript = try await dependencies.transcripts.transcript(for: recordingID) else {
            throw SummaryFailure.noTranscript
        }
        guard !transcript.segments.isEmpty else {
            throw SummaryFailure.emptyTranscript
        }
        return transcript
    }

    /// Progress arrives in order through a stream, and only that of the current attempt.
    private func summarize(
        _ transcript: Transcript,
        with session: TextGenerationSession
    ) async throws -> (summary: TranscriptSummary, title: String?) {
        let recordingID = transcript.recordingID
        let (updates, continuation) = AsyncStream.makeStream(of: TranscriptSummarizer.Progress.self)
        let observer = Task { [weak self] in
            for await update in updates {
                self?.apply(update, to: recordingID)
            }
        }
        defer {
            continuation.finish()
            observer.cancel()
        }
        let language = dependencies.language()
        let summarizer = TranscriptSummarizer(
            generator: session.generator,
            settings: session.settings,
            language: language
        )
        let output = try await summarizer.summarize(transcript) { continuation.yield($0) }
        continuation.finish()
        await observer.value
        try Task.checkCancellation()
        let summary = TranscriptSummary(
            recordingID: recordingID,
            modelID: session.modelID,
            language: language.code,
            transcriptCreatedAt: transcript.createdAt,
            createdAt: dependencies.now(),
            text: output.text,
            parts: output.parts
        )
        return (summary, output.title)
    }

    private func apply(_ update: TranscriptSummarizer.Progress, to recordingID: UUID) {
        guard active?.recordingID == recordingID, active?.stopReason == nil else {
            return
        }
        switch update {
        case .writingParts(let completed, let total):
            setState(.summarizingParts(completed: completed, total: total), of: recordingID)
        case .combining:
            setState(.combining, of: recordingID)
        }
    }

    /// Where a summary goes when it did not finish. A stop asked for by someone decides that, whatever the error was.
    private func settle(_ recordingID: UUID, after error: any Error) {
        switch active?.stopReason {
        case .removed, .cancelled:
            removeJob(recordingID)
        case .recordingPriority:
            setState(.queued, of: recordingID)
        case nil:
            if error is CancellationError {
                removeJob(recordingID)
                return
            }
            let failure = SummaryFailure(error)
            Self.logger.error("Summarizing failed: \(String(describing: failure), privacy: .public)")
            setState(.failed(failure), of: recordingID)
        }
    }
}
