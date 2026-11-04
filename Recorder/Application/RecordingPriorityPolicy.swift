import Foundation
import Observation

/// Keeps model work out of the way of capture: from the moment a recording starts preparing until its media is safe,
/// the model manager holds back downloads and verification.
@MainActor
final class RecordingPriorityPolicy {
    private let coordinator: RecordingCoordinator
    private let models: ModelManager

    init(coordinator: RecordingCoordinator, models: ModelManager) {
        self.coordinator = coordinator
        self.models = models
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
    }
}
