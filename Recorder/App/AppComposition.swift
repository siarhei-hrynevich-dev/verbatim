import SwiftUI

/// The composition root: connects the app's concrete services to the contracts the app core depends on.
@MainActor
enum AppComposition {
    /// The view models that outlive their windows, sharing one set of services.
    struct ViewModels {
        let recorder: RecorderViewModel
        let library: LibraryViewModel
        let viewer: ViewerViewModel
        /// Renders the Viewer's video. Created here because it is the one view tied to the concrete player.
        let viewerVideoSurface: AnyView
    }

    /// With a scenario, a window starts on that design state; capture and the library stay untouched unless the user
    /// returns to Live.
    static func makeViewModels(
        recorderScenario: RecorderPreviewScenario?,
        libraryScenario: LibraryPreviewScenario?,
        viewerScenario: ViewerPreviewScenario?
    ) -> ViewModels {
        let engine = ScreenCaptureEngine()
        let permissions = SystemCapturePermissions()
        let store = FileRecordingStore(defaults: .standard, defaultFolder: FileRecordingStore.defaultFolder())
        let systemActions = WorkspaceSystemActions()
        let library = LibraryService(
            repository: SQLiteRecordingRepository(databaseURL: SQLiteRecordingRepository.defaultDatabaseURL()),
            fileStore: LocalRecordingFileStore(systemActions: systemActions),
            thumbnails: VideoThumbnailProvider(cacheFolder: VideoThumbnailProvider.defaultCacheFolder()),
            destinations: store
        )
        let coordinator = RecordingCoordinator(
            engine: engine,
            permissions: permissions,
            destinations: store,
            metadataStore: store,
            library: library
        )
        let recorder = RecorderViewModel(
            dependencies: RecorderViewModel.Dependencies(
                coordinator: coordinator,
                sourceProvider: CaptureSourceDiscovery(),
                levelPreviewEngine: engine,
                permissions: permissions,
                storage: store,
                preferencesStore: UserDefaultsRecordingPreferencesStore(defaults: .standard),
                systemActions: systemActions
            )
        )
        if let recorderScenario {
            recorder.apply(recorderScenario)
        }
        let playback = AVPlaybackService()
        return ViewModels(
            recorder: recorder,
            library: LibraryViewModel(service: library, previewScenario: libraryScenario),
            viewer: ViewerViewModel(library: library, playback: playback, previewScenario: viewerScenario),
            viewerVideoSurface: AnyView(AVPlayerSurface(service: playback))
        )
    }
}
