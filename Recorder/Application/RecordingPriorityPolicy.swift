import Foundation
import Observation

/// Keeps model work out of the way of capture: from the moment a recording starts preparing until its media is safe,
/// both model managers hold back downloads and verification, and transcription and summaries stop and wait.
@MainActor
final class RecordingPriorityPolicy {
    private let coordinator: RecordingCoordinator
    private let speechModels: SpeechModelManager
    private let languageModels: LanguageModelManager
    private let processing: ProcessingCoordinator
    private let summaries: SummaryCoordinator

    init(
        coordinator: RecordingCoordinator,
        speechModels: SpeechModelManager,
        languageModels: LanguageModelManager,
        processing: ProcessingCoordinator,
        summaries: SummaryCoordinator
    ) {
        self.coordinator = coordinator
        self.speechModels = speechModels
        self.languageModels = languageModels
        self.processing = processing
        self.summaries = summaries
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
        processing.setRecordingActive(isRecordingActive)
        summaries.setRecordingActive(isRecordingActive)
    }
}
