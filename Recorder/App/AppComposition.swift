import Foundation

/// The composition root: connects the Recorder's concrete services to the contracts the app core depends on.
@MainActor
enum AppComposition {
    /// With a `scenario`, the window starts on that design state; capture stays idle unless the user returns to Live.
    static func makeRecorderViewModel(scenario: RecorderPreviewScenario?) -> RecorderViewModel {
        let engine = ScreenCaptureEngine()
        let permissions = SystemCapturePermissions()
        let store = FileRecordingStore(defaults: .standard, defaultFolder: FileRecordingStore.defaultFolder())
        let coordinator = RecordingCoordinator(
            engine: engine,
            permissions: permissions,
            destinations: store,
            repository: store
        )
        let viewModel = RecorderViewModel(
            dependencies: RecorderViewModel.Dependencies(
                coordinator: coordinator,
                sourceProvider: CaptureSourceDiscovery(),
                levelPreviewEngine: engine,
                permissions: permissions,
                storage: store,
                preferencesStore: UserDefaultsRecordingPreferencesStore(defaults: .standard),
                systemActions: WorkspaceSystemActions()
            )
        )
        if let scenario {
            viewModel.apply(scenario)
        }
        return viewModel
    }
}
