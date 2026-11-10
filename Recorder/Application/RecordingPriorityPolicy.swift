import Foundation
import Observation

/// Keeps model work out of the way of capture: from the moment a recording starts preparing until its media is safe,
/// the model managers hold back downloads and verification, and transcription, summaries and indexing stop and wait.
@MainActor
final class RecordingPriorityPolicy {
    private let coordinator: RecordingCoordinator
    private let speechModels: SpeechModelManager
    private let languageModels: LanguageModelManager
    private let embeddingModels: EmbeddingModelManager
    private let processing: ProcessingCoordinator
    private let summaries: SummaryCoordinator
    private let indexing: IndexingCoordinator

    init(
        coordinator: RecordingCoordinator,
        speechModels: SpeechModelManager,
        languageModels: LanguageModelManager,
        embeddingModels: EmbeddingModelManager,
        processing: ProcessingCoordinator,
        summaries: SummaryCoordinator,
        indexing: IndexingCoordinator
    ) {
        self.coordinator = coordinator
        self.speechModels = speechModels
        self.languageModels = languageModels
        self.embeddingModels = embeddingModels
        self.processing = processing
        self.summaries = summaries
        self.indexing = indexing
    }

    func start() {
        // Only the recording state is tracked; acting on it reads model state, which must not re-trigger this.
        let isRecordingActive = withObservationTracking {
            !coordinator.state.acceptsStart
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.start()
            }
        }
        speechModels.setRecordingActive(isRecordingActive)
        languageModels.setRecordingActive(isRecordingActive)
        embeddingModels.setRecordingActive(isRecordingActive)
        processing.setRecordingActive(isRecordingActive)
        summaries.setRecordingActive(isRecordingActive)
        indexing.setRecordingActive(isRecordingActive)
    }
}
