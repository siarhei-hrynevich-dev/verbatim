import Foundation

/// One recording's indexing steps. Chunks are replaced in one transaction and vectors are stored a batch at a time, so
/// a job stopped at any point leaves a consistent index and continues from the vectors already made.
extension IndexingCoordinator {
    /// Chunks embedded per call: enough to keep the model busy, few enough to stop soon when a recording starts.
    static let embeddingBatchSize = 8

    func run(_ recordingID: UUID) async {
        var sessionID: UUID?
        do {
            try await updateChunks(of: recordingID)
            try Task.checkCancellation()
            if let space = dependencies.embeddings.readySpace {
                let pending = try await dependencies.index.pendingEmbeddings(for: recordingID, in: space)
                if !pending.isEmpty {
                    let session = try await dependencies.embeddings.acquireEmbedder()
                    sessionID = session.id
                    try await embed(recordingID, in: session)
                }
            }
            completed(recordingID)
        } catch {
            settle(recordingID, after: error)
        }
        // The embedder was local to the steps above, so the model can go once the provider lets it.
        if let sessionID {
            dependencies.embeddings.release(sessionID: sessionID)
        }
        finishActiveJob()
    }

    /// Makes chunks again for whichever of the transcript and summary changed since the last time, and removes those of
    /// one that is gone. A summary of an earlier transcript is still indexed: it is what the Viewer shows.
    private func updateChunks(of recordingID: UUID) async throws {
        let transcript = try await dependencies.transcripts.transcript(for: recordingID)
        let summary = try await dependencies.summaries.summary(for: recordingID)
        let indexed = try await dependencies.index.indexState(for: recordingID)
        let current = SearchIndexState(
            transcriptCreatedAt: transcript?.createdAt,
            summaryCreatedAt: summary?.createdAt
        )
        var kinds: Set<SearchChunkKind> = []
        var chunks: [SearchChunk] = []
        if current.transcriptCreatedAt != indexed.transcriptCreatedAt {
            kinds.insert(.transcript)
            chunks += transcript.map(SearchChunker.chunks(of:)) ?? []
        }
        if current.summaryCreatedAt != indexed.summaryCreatedAt {
            kinds.formUnion([.summary, .summaryPart])
            chunks += summary.map(SearchChunker.chunks(of:)) ?? []
        }
        guard !kinds.isEmpty else {
            return
        }
        try Task.checkCancellation()
        try await dependencies.index.replaceChunks(chunks, ofKinds: kinds, for: recordingID, state: current)
    }

    /// Reads what still needs vectors in the session's space, which is the space of the model actually loaded.
    private func embed(_ recordingID: UUID, in session: EmbeddingSession) async throws {
        let pending = try await dependencies.index.pendingEmbeddings(for: recordingID, in: session.space)
        var completed = 0
        for start in stride(from: 0, to: pending.count, by: Self.embeddingBatchSize) {
            try Task.checkCancellation()
            setProgress(.embedding(completed: completed, total: pending.count), of: recordingID)
            let batch = pending[start..<min(start + Self.embeddingBatchSize, pending.count)]
            let vectors = try await session.embedder.embed(batch.map(\.text), as: .passage)
            guard vectors.count == batch.count else {
                throw IndexingFailure.embeddingFailed(detail: "The model returned \(vectors.count) of \(batch.count)")
            }
            let stored = Dictionary(uniqueKeysWithValues: zip(batch.map(\.chunkID), vectors))
            try await dependencies.index.storeEmbeddings(stored, in: session.space)
            completed += batch.count
        }
    }

    private func setProgress(_ state: IndexingJob.State, of recordingID: UUID) {
        guard active?.recordingID == recordingID, active?.stopReason == nil else {
            return
        }
        setState(state, of: recordingID)
    }

    /// Where a job goes when it did not finish. A stop asked for by someone decides that, whatever the error was.
    private func settle(_ recordingID: UUID, after error: any Error) {
        switch active?.stopReason {
        case .removed:
            removeJob(recordingID)
        case .recordingPriority:
            setState(.queued, of: recordingID)
        case nil:
            if error is CancellationError {
                removeJob(recordingID)
                return
            }
            let failure = IndexingFailure(error)
            Self.logger.error("Indexing failed: \(String(describing: failure), privacy: .public)")
            setState(.failed(failure), of: recordingID)
        }
    }
}
