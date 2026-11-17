import Observation
import os

/// Runs audio capture for the Ready state's meters, writing nothing. Owned by the Recorder window's view model
/// because it ends with the setup screen, unlike a recording.
@MainActor
@Observable
final class LevelPreviewController {
    private(set) var levels = AudioLevels.silent

    @ObservationIgnored private let engine: any CaptureEngine
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var sources: Sources?

    private struct Sources: Equatable {
        let microphone: Microphone?
        let capturesSystemAudio: Bool
    }

    init(engine: any CaptureEngine) {
        self.engine = engine
    }

    /// Makes the preview capture exactly these sources, restarting only if they changed.
    func run(microphone: Microphone?, capturesSystemAudio: Bool) {
        let requested = Sources(microphone: microphone, capturesSystemAudio: capturesSystemAudio)
        guard requested != sources else {
            return
        }
        stop()
        guard microphone != nil || capturesSystemAudio else {
            return
        }
        sources = requested
        let engine = engine
        task = Task { [weak self] in
            do {
                let session = try await engine.startLevelPreview(
                    microphone: microphone,
                    capturesSystemAudio: capturesSystemAudio
                )
                for await event in session.events {
                    if case .levels(let levels) = event, !Task.isCancelled {
                        self?.levels = levels
                    }
                }
                await session.stopCapture()
            } catch {
                // The meters only stay still here; starting a recording reports the same problem with its fix.
                Self.logger.notice("Level preview did not start: \(String(describing: error))")
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        sources = nil
        levels = .silent
    }

    private static let logger = Logger(category: "Recorder")
}
