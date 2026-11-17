import Foundation
import os

/// Gives indexing and search the selected installed embedding model. One copy is loaded and shared by every session;
/// it holds a lease on the model's files meanwhile, and goes a short while after the last session ends, or as soon as
/// one ends while recording.
@MainActor
final class LocalEmbeddingProvider: EmbeddingProvider {
    private struct LoadedModel {
        let lease: EmbeddingModelLease
        let embedder: any TextEmbedder
    }

    private let models: EmbeddingModelManager
    private let runtime: any LocalEmbeddingRuntime
    private let idleDelay: Duration
    private var loaded: LoadedModel?
    /// A load in progress, which a second request waits for rather than loading another copy.
    private var loading: Task<LoadedModel, any Error>?
    private var sessions: Set<UUID> = []
    private var idleRelease: Task<Void, Never>?
    private(set) var isRecordingActive = false

    /// An agent asks follow-up questions within seconds; a minute keeps them from reloading the model each time.
    init(models: EmbeddingModelManager, runtime: any LocalEmbeddingRuntime, idleDelay: Duration = .seconds(60)) {
        self.models = models
        self.runtime = runtime
        self.idleDelay = idleDelay
    }

    var readySpace: EmbeddingSpace? {
        guard case .ready(let model) = models.selectionStatus else {
            return nil
        }
        return model.space
    }

    func prepareForUse() async {
        await models.reconcile()
    }

    func acquireEmbedder() async throws -> EmbeddingSession {
        guard !isRecordingActive else {
            throw CancellationError()
        }
        idleRelease?.cancel()
        idleRelease = nil
        let model = try await loadedModel()
        // Recording may have started while the model loaded; the session ends at once in that case.
        try Task.checkCancellation()
        let id = UUID()
        sessions.insert(id)
        return EmbeddingSession(id: id, space: model.lease.model.space, embedder: model.embedder)
    }

    func release(sessionID: UUID) {
        guard sessions.remove(sessionID) != nil, sessions.isEmpty else {
            return
        }
        if isRecordingActive {
            unload()
        } else {
            scheduleIdleRelease()
        }
    }

    func setRecordingActive(_ isActive: Bool) {
        isRecordingActive = isActive
        if isActive, sessions.isEmpty {
            unload()
        }
    }

    // MARK: - Loading

    /// The loaded model, unless another model has been selected since and nothing uses this one any more.
    private func loadedModel() async throws -> LoadedModel {
        if let loaded {
            guard sessions.isEmpty, loaded.lease.model.space != readySpace else {
                return loaded
            }
            unload()
        }
        if let loading {
            return try await loading.value
        }
        let task = Task { try await load() }
        loading = task
        defer { loading = nil }
        let model = try await task.value
        loaded = model
        return model
    }

    private func load() async throws -> LoadedModel {
        let lease: EmbeddingModelLease
        do {
            lease = try models.acquireSelectedModel()
        } catch {
            throw IndexingFailure(error)
        }
        do {
            let embedder = try await runtime.loadEmbedder(for: lease.model)
            return LoadedModel(lease: lease, embedder: embedder)
        } catch {
            models.release(lease)
            await runtime.releaseMemory()
            if error is CancellationError {
                throw error
            }
            let modelID = lease.model.space.modelID
            Self.logger.error("Could not load \(modelID, privacy: .public): \(String(describing: error))")
            throw IndexingFailure.modelLoadFailed(detail: error.localizedDescription)
        }
    }

    // MARK: - Unloading

    private func scheduleIdleRelease() {
        idleRelease?.cancel()
        idleRelease = Task { [weak self, idleDelay] in
            do {
                try await Task.sleep(for: idleDelay)
            } catch {
                return
            }
            self?.unloadIfIdle()
        }
    }

    private func unloadIfIdle() {
        if sessions.isEmpty {
            unload()
        }
    }

    /// Lets go of the model, whose memory returns once the last session's embedder is gone too.
    private func unload() {
        idleRelease?.cancel()
        idleRelease = nil
        guard let loaded else {
            return
        }
        self.loaded = nil
        models.release(loaded.lease)
        // Only returns cached buffers, which takes a moment and cannot fail, so nothing needs to wait for it.
        let runtime = runtime
        Task {
            await runtime.releaseMemory()
        }
    }

    private static let logger = Logger(category: "Search")
}
