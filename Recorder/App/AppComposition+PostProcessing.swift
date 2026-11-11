import Foundation

/// The models and the work done with them after a recording: transcription, summaries and the search index.
extension AppComposition {
    /// The models and the work done with them after a recording, created together because each depends on the last:
    /// a transcript is summarized, and both are indexed for search.
    struct PostProcessing {
        let speechModels: SpeechModelManager
        let processing: ProcessingCoordinator
        let languageModels: LanguageModelManager
        let summaryPreferences: SummaryPreferences
        let summaries: SummaryCoordinator
        let embeddingModels: EmbeddingModelManager
        let indexing: IndexingCoordinator
        let search: RecordingSearchService
        /// The index search reads, shared so that readers see the same cached vectors.
        let searchIndex: SQLiteSearchIndexRepository
    }

    private static func makeProcessing(
        databaseURL: URL,
        library: LibraryService,
        modelManager: SpeechModelManager,
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
        library.addRemovalObserver(processing)
        return processing
    }

    private static func makeModelManager() -> SpeechModelManager {
        let storage = WhisperModelProvider.defaultStorageLocation()
        return SpeechModelManager(
            provider: WhisperModelProvider(storageLocation: storage),
            registryStore: JSONModelRegistryStore(fileURL: JSONModelRegistryStore.defaultFileURL(in: storage)),
            settings: UserDefaultsSettingsRepository(defaults: .standard)
        )
    }

    private static func makeLanguageModelManager(selection: any ModelSelectionStore) -> LanguageModelManager {
        let storage = HubLanguageModelProvider.defaultStorageLocation()
        return LanguageModelManager(
            catalog: LanguageModelCatalog.curated,
            provider: HubLanguageModelProvider(storageLocation: storage),
            registryStore: JSONModelRegistryStore(fileURL: JSONModelRegistryStore.defaultFileURL(in: storage)),
            selection: selection
        )
    }

    private static func makeEmbeddingModelManager() -> EmbeddingModelManager {
        let storage = HubEmbeddingModelProvider.defaultStorageLocation()
        return EmbeddingModelManager(
            catalog: EmbeddingModelCatalog.curated,
            provider: HubEmbeddingModelProvider(storageLocation: storage),
            registryStore: JSONModelRegistryStore(fileURL: JSONModelRegistryStore.defaultFileURL(in: storage)),
            selection: UserDefaultsEmbeddingSelectionStore(defaults: .standard)
        )
    }

    /// The search index's model, its queue and the search over it.
    private struct Indexing {
        let models: EmbeddingModelManager
        let coordinator: IndexingCoordinator
        let search: RecordingSearchService
        let index: SQLiteSearchIndexRepository
    }

    /// Indexing waits for transcription and summaries, and is told about each transcript and summary stored.
    private static func makeIndexing(
        databaseURL: URL,
        library: LibraryService,
        processing: ProcessingCoordinator,
        summaries: SummaryCoordinator
    ) -> Indexing {
        let embeddingModels = makeEmbeddingModelManager()
        let embeddings = LocalEmbeddingProvider(models: embeddingModels, runtime: MLXEmbeddingRuntime())
        let index = SQLiteSearchIndexRepository(databaseURL: databaseURL)
        let indexing = IndexingCoordinator(
            dependencies: IndexingCoordinator.Dependencies(
                transcripts: SQLiteTranscriptRepository(databaseURL: databaseURL),
                summaries: SQLiteSummaryRepository(databaseURL: databaseURL),
                index: index,
                embeddings: embeddings,
                isPostProcessingBusy: { processing.hasActiveJobs || summaries.hasActiveJobs }
            )
        )
        library.addRemovalObserver(indexing)
        processing.onTranscriptStored = { recordingID in
            summaries.enqueueIfModelReady(recordingID)
            indexing.enqueue(recordingID)
        }
        summaries.onSummaryStored = { recordingID in
            indexing.enqueue(recordingID)
        }
        return Indexing(
            models: embeddingModels,
            coordinator: indexing,
            search: RecordingSearchService(index: index, embeddings: embeddings),
            index: index
        )
    }

    static func makePostProcessing(
        databaseURL: URL,
        library: LibraryService,
        preferences: AppPreferences
    ) -> PostProcessing {
        let speechModels = makeModelManager()
        let processing = makeProcessing(
            databaseURL: databaseURL,
            library: library,
            modelManager: speechModels,
            preferences: preferences
        )
        let settings = UserDefaultsSummarySettingsRepository(defaults: .standard)
        let summaryPreferences = SummaryPreferences(repository: settings)
        let languageModels = makeLanguageModelManager(selection: settings)
        let summaries = SummaryCoordinator(
            dependencies: SummaryCoordinator.Dependencies(
                transcripts: SQLiteTranscriptRepository(databaseURL: databaseURL),
                summaries: SQLiteSummaryRepository(databaseURL: databaseURL),
                generation: LocalTextGenerationProvider(
                    models: languageModels,
                    runtime: MLXTextGenerationRuntime(),
                    preferences: summaryPreferences
                ),
                isTranscriptionBusy: { processing.hasActiveJobs },
                language: { summaryPreferences.language }
            )
        )
        library.addRemovalObserver(summaries)
        let indexing = makeIndexing(
            databaseURL: databaseURL,
            library: library,
            processing: processing,
            summaries: summaries
        )
        return PostProcessing(
            speechModels: speechModels,
            processing: processing,
            languageModels: languageModels,
            summaryPreferences: summaryPreferences,
            summaries: summaries,
            embeddingModels: indexing.models,
            indexing: indexing.coordinator,
            search: indexing.search,
            searchIndex: indexing.index
        )
    }

    /// Holds model, transcription, summary and indexing work back while recording.
    static func makeRecordingPriority(
        coordinator: RecordingCoordinator,
        post: PostProcessing
    ) -> RecordingPriorityPolicy {
        RecordingPriorityPolicy(
            coordinator: coordinator,
            speechModels: post.speechModels,
            languageModels: post.languageModels,
            embeddingModels: post.embeddingModels,
            processing: post.processing,
            summaries: post.summaries,
            indexing: post.indexing
        )
    }
}
