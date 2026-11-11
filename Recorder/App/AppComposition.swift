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
        let modelManager: SpeechModelManager
        let languageModelManager: LanguageModelManager
        let embeddingModelManager: EmbeddingModelManager
        let processing: ProcessingCoordinator
        let summaries: SummaryCoordinator
        let indexing: IndexingCoordinator
        /// The MCP server through which AI agents on this Mac search and read recordings.
        let agentServer: AgentServerController
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
        let post = makePostProcessing(databaseURL: databaseURL, library: library, preferences: preferences)
        let processing = post.processing
        let (coordinator, recorder) = makeRecording(
            library: library,
            processing: processing,
            store: store,
            systemActions: systemActions,
            scenario: recorderScenario
        )
        let playback = AVPlaybackService()
        let agentServer = makeAgentServer(databaseURL: databaseURL, post: post)
        let settings = makeSettings(
            SettingsSources(
                library: library,
                recorder: recorder,
                systemActions: systemActions,
                preferences: preferences,
                models: post,
                agentServer: agentServer,
                scenario: settingsScenario
            )
        )
        return ViewModels(
            recorder: recorder,
            library: makeLibraryViewModel(library: library, post: post, scenario: libraryScenario),
            viewer: ViewerViewModel(
                library: library,
                playback: playback,
                processing: processing,
                summaries: post.summaries,
                previewScenario: viewerScenario
            ),
            settings: settings,
            preferences: preferences,
            modelManager: post.speechModels,
            languageModelManager: post.languageModels,
            embeddingModelManager: post.embeddingModels,
            processing: processing,
            summaries: post.summaries,
            indexing: post.indexing,
            agentServer: agentServer,
            recordingPriority: makeRecordingPriority(coordinator: coordinator, post: post),
            viewerVideoSurface: AnyView(AVPlayerSurface(service: playback))
        )
    }

    private static func makeLibraryViewModel(
        library: LibraryService,
        post: PostProcessing,
        scenario: LibraryPreviewScenario?
    ) -> LibraryViewModel {
        LibraryViewModel(
            service: library,
            processing: post.processing,
            summaries: post.summaries,
            indexing: post.indexing,
            previewScenario: scenario
        )
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

    /// The MCP server reads the Library through its own connections and answers with what the coordinators hold.
    private static func makeAgentServer(databaseURL: URL, post: PostProcessing) -> AgentServerController {
        let metadata = AppMetadata(infoDictionary: Bundle.main.infoDictionary ?? [:])
        let knowledge = RecordingKnowledgeService(
            dependencies: RecordingKnowledgeService.Dependencies(
                recordings: SQLiteRecordingRepository(databaseURL: databaseURL),
                transcripts: SQLiteTranscriptRepository(databaseURL: databaseURL),
                summaries: SQLiteSummaryRepository(databaseURL: databaseURL),
                index: post.searchIndex,
                search: post.search,
                activity: { [processing = post.processing, summaries = post.summaries, indexing = post.indexing] id in
                    RecordingActivity(
                        transcription: processing.job(for: id)?.state,
                        summary: summaries.job(for: id)?.state,
                        indexing: indexing.job(for: id)?.state
                    )
                }
            )
        )
        let endpoint = MCPEndpoint(toolbox: MCPToolbox(knowledge: knowledge), serverVersion: metadata.version)
        return AgentServerController(
            host: MCPHTTPServer(endpoint: endpoint),
            repository: UserDefaultsAgentServerRepository(defaults: .standard)
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

    /// What the Settings window works with, all of it shared with other windows.
    private struct SettingsSources {
        let library: LibraryService
        let recorder: RecorderViewModel
        let systemActions: any SystemActions
        let preferences: AppPreferences
        let models: PostProcessing
        let agentServer: AgentServerController
        let scenario: SettingsPreviewScenario?
    }

    private static func makeSettings(_ sources: SettingsSources) -> SettingsViewModel {
        let models = sources.models
        let recorder = sources.recorder
        let settings = SettingsViewModel(
            dependencies: SettingsViewModel.Dependencies(
                preferences: sources.preferences,
                loginItem: SMAppServiceLoginItem(),
                recordingsStorage: sources.library,
                systemActions: sources.systemActions,
                modelManager: models.speechModels,
                languageModelManager: models.languageModels,
                embeddingModelManager: models.embeddingModels,
                summaryPreferences: models.summaryPreferences,
                agentServer: sources.agentServer,
                metadata: AppMetadata(infoDictionary: Bundle.main.infoDictionary ?? [:]),
                chooseRecordingsFolder: { await recorder.useChosenFolder($0) }
            )
        )
        if let scenario = sources.scenario {
            settings.apply(scenario)
        }
        return settings
    }
}
