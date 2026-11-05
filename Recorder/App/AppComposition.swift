import SwiftUI

/// The composition root: connects the app's concrete services to the contracts the app core depends on.
@MainActor
enum AppComposition {
    /// The view models that outlive their windows, sharing one set of services.
    struct ViewModels {
        let recorder: RecorderViewModel
        let library: LibraryViewModel
        let viewer: ViewerViewModel
        let settings: SettingsViewModel
        let preferences: AppPreferences
        let modelManager: ModelManager
        let processing: ProcessingCoordinator
        /// Holds model and transcription work back while recording.
        let recordingPriority: RecordingPriorityPolicy
        /// Renders the Viewer's video. Created here because it is the one view tied to the concrete player.
        let viewerVideoSurface: AnyView
    }

    /// With a scenario, a window starts on that design state; capture and the library stay untouched unless the user
    /// returns to Live.
    static func makeViewModels(
        recorderScenario: RecorderPreviewScenario?,
        libraryScenario: LibraryPreviewScenario?,
        viewerScenario: ViewerPreviewScenario?,
        settingsScenario: SettingsPreviewScenario?
    ) -> ViewModels {
        let store = FileRecordingStore(defaults: .standard, defaultFolder: FileRecordingStore.defaultFolder())
        let systemActions = WorkspaceSystemActions()
        let databaseURL = SQLiteRecordingRepository.defaultDatabaseURL()
        let library = makeLibrary(databaseURL: databaseURL, store: store, systemActions: systemActions)
        let preferences = AppPreferences(repository: UserDefaultsSettingsRepository(defaults: .standard))
        let modelManager = makeModelManager()
        let processing = makeProcessing(
            databaseURL: databaseURL,
            library: library,
            modelManager: modelManager,
            preferences: preferences
        )
        let (coordinator, recorder) = makeRecording(
            library: library,
            processing: processing,
            store: store,
            systemActions: systemActions,
            scenario: recorderScenario
        )
        let playback = AVPlaybackService()
        let settings = makeSettings(
            library: library,
            recorder: recorder,
            systemActions: systemActions,
            preferences: preferences,
            modelManager: modelManager
        )
        if let settingsScenario {
            settings.apply(settingsScenario)
        }
        return ViewModels(
            recorder: recorder,
            library: LibraryViewModel(service: library, processing: processing, previewScenario: libraryScenario),
            viewer: ViewerViewModel(
                library: library,
                playback: playback,
                processing: processing,
                previewScenario: viewerScenario
            ),
            settings: settings,
            preferences: preferences,
            modelManager: modelManager,
            processing: processing,
            recordingPriority: RecordingPriorityPolicy(
                coordinator: coordinator,
                models: modelManager,
                processing: processing
            ),
            viewerVideoSurface: AnyView(AVPlayerSurface(service: playback))
        )
    }

    private static func makeProcessing(
        databaseURL: URL,
        library: LibraryService,
        modelManager: ModelManager,
        preferences: AppPreferences
    ) -> ProcessingCoordinator {
        let store = SQLiteTranscriptRepository(databaseURL: databaseURL)
        let processing = ProcessingCoordinator(
            dependencies: ProcessingCoordinator.Dependencies(
                jobs: store,
                transcripts: store,
                transcription: WhisperTranscriptionService(),
                models: modelManager,
                library: library,
                files: FileTranscriptStore(),
                language: { preferences.settings.transcriptionLanguage }
            )
        )
        library.removalObserver = processing
        return processing
    }

    private static func makeLibrary(
        databaseURL: URL,
        store: FileRecordingStore,
        systemActions: WorkspaceSystemActions
    ) -> LibraryService {
        LibraryService(
            repository: SQLiteRecordingRepository(databaseURL: databaseURL),
            fileStore: LocalRecordingFileStore(systemActions: systemActions),
            thumbnails: VideoThumbnailProvider(cacheFolder: VideoThumbnailProvider.defaultCacheFolder()),
            destinations: store
        )
    }

    private static func makeRecording(
        library: LibraryService,
        processing: ProcessingCoordinator,
        store: FileRecordingStore,
        systemActions: WorkspaceSystemActions,
        scenario: RecorderPreviewScenario?
    ) -> (RecordingCoordinator, RecorderViewModel) {
        let engine = ScreenCaptureEngine()
        let permissions = SystemCapturePermissions()
        let coordinator = RecordingCoordinator(
            engine: engine,
            permissions: permissions,
            destinations: store,
            metadataStore: store,
            library: library,
            transcriptionScheduler: processing
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
        if let scenario {
            recorder.apply(scenario)
        }
        return (coordinator, recorder)
    }

    private static func makeSettings(
        library: LibraryService,
        recorder: RecorderViewModel,
        systemActions: any SystemActions,
        preferences: AppPreferences,
        modelManager: ModelManager
    ) -> SettingsViewModel {
        SettingsViewModel(
            dependencies: SettingsViewModel.Dependencies(
                preferences: preferences,
                loginItem: SMAppServiceLoginItem(),
                recordingsStorage: library,
                systemActions: systemActions,
                modelManager: modelManager,
                metadata: AppMetadata(infoDictionary: Bundle.main.infoDictionary ?? [:]),
                chooseRecordingsFolder: { await recorder.useChosenFolder($0) }
            )
        )
    }

    private static func makeModelManager() -> ModelManager {
        let storage = WhisperModelProvider.defaultStorageLocation()
        return ModelManager(
            provider: WhisperModelProvider(storageLocation: storage),
            registryStore: JSONModelRegistryStore(fileURL: JSONModelRegistryStore.defaultFileURL(in: storage)),
            settings: UserDefaultsSettingsRepository(defaults: .standard)
        )
    }
}
