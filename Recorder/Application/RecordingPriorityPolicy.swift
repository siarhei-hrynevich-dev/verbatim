import Foundation
import Observation

/// Keeps model work out of the way of capture: from the moment a recording starts preparing until its media is safe,
/// the model manager holds back downloads and verification, and transcription stops and waits.
@MainActor
final class RecordingPriorityPolicy {
    private let coordinator: RecordingCoordinator
    private let models: ModelManager
    private let processing: ProcessingCoordinator

    init(coordinator: RecordingCoordinator, models: ModelManager, processing: ProcessingCoordinator) {
        self.coordinator = coordinator
        self.models = models
        self.processing = processing
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
        models.setRecordingActive(isRecordingActive)
        processing.setRecordingActive(isRecordingActive)
    }
}
