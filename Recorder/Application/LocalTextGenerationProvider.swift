import Foundation
import os

/// Gives summarization the selected installed language model: holds a lease on its files so they cannot be removed
/// meanwhile, loads it through the runtime, and pairs it with the settings chosen for it.
@MainActor
final class LocalTextGenerationProvider: TextGenerationProvider {
    private let models: LanguageModelManager
    private let runtime: any LocalTextGenerationRuntime
    private let preferences: SummaryPreferences
    private var leases: [UUID: LanguageModelLease] = [:]

    init(models: LanguageModelManager, runtime: any LocalTextGenerationRuntime, preferences: SummaryPreferences) {
        self.models = models
        self.runtime = runtime
        self.preferences = preferences
    }

    var hasUsableModel: Bool {
        if case .ready = models.selectionStatus {
            return true
        }
        return false
    }

    func prepareForUse() async {
        await models.reconcile()
    }

    func acquireGenerator() async throws -> TextGenerationSession {
        let lease: LanguageModelLease
        do {
            lease = try models.acquireSelectedModel()
        } catch {
            throw SummaryFailure(error)
        }
        guard let model = models.model(withID: lease.model.id) else {
            models.release(lease)
            throw SummaryFailure.modelUnavailable(lease.model.id)
        }
        let generator: any TextGenerator
        do {
            generator = try await runtime.loadGenerator(for: lease.model)
        } catch {
            models.release(lease)
            await runtime.releaseMemory()
            if error is CancellationError {
                throw error
            }
            Self.logger.error("Could not load \(model.id, privacy: .public): \(String(describing: error))")
            throw SummaryFailure.modelLoadFailed(detail: error.localizedDescription)
        }
        let session = TextGenerationSession(
            id: lease.id,
            modelID: model.id,
            settings: preferences.settings(for: model),
            generator: generator
        )
        leases[session.id] = lease
        return session
    }

    func release(sessionID: UUID) async {
        if let lease = leases.removeValue(forKey: sessionID) {
            models.release(lease)
        }
        await runtime.releaseMemory()
    }

    private static let logger = Logger(subsystem: "dev.local.Recorder", category: "Summaries")
}
