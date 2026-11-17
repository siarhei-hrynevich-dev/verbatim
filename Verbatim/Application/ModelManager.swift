import Foundation
import Observation
import os

/// The single owner of one kind of model's state: what is available and installed, which model is selected, and every
/// installation in progress. There is one for speech models and one for language models; each outlives the Settings
/// window, so a download continues with the window closed.
///
/// State changes happen synchronously on the main actor before any suspension, so a duplicate request is rejected by
/// the state check. The work itself runs off the main actor in the provider, and no model is ever loaded here.
@MainActor
@Observable
final class ModelManager<Model: InstallableModel> {
    /// The selected model as far as it can be used right now.
    enum SelectionStatus: Equatable, Sendable {
        case none
        case ready(Model)
        /// Selected, but its files are gone or damaged. Nothing is switched or downloaded without being asked.
        case unavailable(Model)
    }

    /// Why an install stopped, when that was intended rather than a failure.
    enum StopReason {
        case cancelled
        case pausedForRecording
    }

    struct ActiveInstall {
        let token: UUID
        let task: Task<Void, Never>
    }

    let catalog: [Model]

    private(set) var states: [Model.ID: ModelInstallState] = [:]
    private(set) var selectedModelID: Model.ID?
    private(set) var supportedModelIDs: Set<Model.ID>
    private(set) var storageUsageBytes: Int64 = 0
    /// The last refresh could not reach the repository, so sizes are the ones saved earlier.
    private(set) var isCatalogOutdated = false
    /// A failure reading or writing the registry, which does not belong to any one model.
    private(set) var storageFailure: ModelManagementError?
    private(set) var hasReconciled = false
    private(set) var isRecordingActive = false
    var registry = ModelRegistry()

    @ObservationIgnored private let provider: any ModelFileProviding<Model>
    @ObservationIgnored let workflow: ModelFileWorkflow<Model>
    @ObservationIgnored private let registryStore: any ModelRegistryStore
    @ObservationIgnored private let selection: any ModelSelectionStore
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored var installs: [Model.ID: ActiveInstall] = [:]
    @ObservationIgnored var stopReasons: [UUID: StopReason] = [:]
    @ObservationIgnored var filesToDiscardFirst: Set<Model.ID> = []
    @ObservationIgnored private var leases: [UUID: Model.ID] = [:]
    /// Advances with each state change, so a slow disk check cannot overwrite what happened during it.
    @ObservationIgnored private var generations: [Model.ID: Int] = [:]
    @ObservationIgnored private var reconcileTask: Task<Void, Never>?
    @ObservationIgnored private var catalogRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var hasLoadedRegistry = false
    @ObservationIgnored private var hasRefreshedCatalog = false

    init(
        catalog: [Model],
        provider: any ModelFileProviding<Model>,
        registryStore: any ModelRegistryStore,
        selection: any ModelSelectionStore,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.catalog = catalog
        self.provider = provider
        workflow = ModelFileWorkflow(provider: provider)
        self.registryStore = registryStore
        self.selection = selection
        self.now = now
        supportedModelIDs = provider.supportedModelIDs()
        selectedModelID = selection.loadSelectedModelID()
    }

    // MARK: - Reading state

    var storageLocation: URL {
        provider.storageLocation
    }

    var recommendedModel: Model? {
        Model.recommended(from: catalog, supportedIDs: supportedModelIDs)
    }

    var selectionStatus: SelectionStatus {
        guard hasReconciled, let selectedModelID, let model = model(withID: selectedModelID) else {
            return .none
        }
        return state(of: selectedModelID).isInstalled ? .ready(model) : .unavailable(model)
    }

    func state(of id: Model.ID) -> ModelInstallState {
        states[id] ?? .notInstalled
    }

    func model(withID id: Model.ID) -> Model? {
        catalog.first { $0.id == id }
    }

    /// The space an installed model takes, or otherwise the last known download size. `nil` until one is known.
    func sizeBytes(of id: Model.ID) -> Int64? {
        if case .installed(let sizeBytes) = state(of: id) {
            return sizeBytes
        }
        return registry.artifactSizes[id]
    }

    // MARK: - Contract for the engines

    /// The selected model's identifier and location, without loading it. Throws `noModelSelected` or
    /// `selectedModelUnavailable`; the caller reports that rather than choosing another model.
    func resolveSelectedModel() throws(ModelManagementError) -> Model.Resolved {
        guard let selectedModelID, let model = model(withID: selectedModelID) else {
            throw .noModelSelected
        }
        guard state(of: selectedModelID).isInstalled else {
            throw .selectedModelUnavailable(selectedModelID)
        }
        return provider.resolve(model)
    }

    /// Resolves the selected model and protects it from removal until `release(_:)`.
    func acquireSelectedModel() throws(ModelManagementError) -> ModelLease<Model> {
        guard let selectedModelID else {
            throw .noModelSelected
        }
        let lease = ModelLease<Model>(id: UUID(), model: try resolveSelectedModel())
        leases[lease.id] = selectedModelID
        return lease
    }

    func release(_ lease: ModelLease<Model>) {
        leases[lease.id] = nil
    }

    // MARK: - Selecting

    /// Only an installed, validated model can be selected. Selecting loads nothing.
    func select(_ id: Model.ID) throws(ModelManagementError) {
        guard state(of: id).isInstalled else {
            throw .modelNotInstalled
        }
        setSelection(id)
    }

    func setSelection(_ id: Model.ID?) {
        selectedModelID = id
        selection.saveSelectedModelID(id)
    }

    /// Recording takes priority: running installs stop, keeping their partial files, and continue when it ends.
    func setRecordingActive(_ isActive: Bool) {
        guard isActive != isRecordingActive else {
            return
        }
        isRecordingActive = isActive
        if isActive {
            pauseInstalls()
        } else {
            resumeWaitingInstalls()
        }
    }

    // MARK: - Removing

    /// Removes an installed model, or what is left of a failed one, leaving recordings and transcripts alone. If it
    /// was selected, none remains selected: another installed model is never chosen on the user's behalf.
    func remove(_ id: Model.ID) async throws(ModelManagementError) {
        guard let model = model(withID: id), state(of: id).acceptsRemoval else {
            throw .modelNotInstalled
        }
        guard !leases.values.contains(id) else {
            throw .modelInUse
        }
        let previous = state(of: id)
        setState(.removing, for: id)
        do {
            try await provider.removeFiles(of: model, includingSharedFiles: !areSharedFilesInUse(by: model))
        } catch {
            setState(previous, for: id)
            await reconcileFiles(of: model)
            await refreshStorageUsage()
            throw error as? ModelManagementError ?? .removalFailed(detail: error.localizedDescription)
        }
        registry.installations[id] = nil
        if selectedModelID == id {
            setSelection(nil)
        }
        setState(.notInstalled, for: id)
        await saveRegistry()
        await refreshStorageUsage()
    }

    // MARK: - Reconciling with the disk

    /// Brings state in line with the files, at launch and when Settings comes forward. Only reads metadata and sizes.
    /// The work belongs to this object rather than the caller, so a window going away cannot cancel a check halfway
    /// and make healthy files look damaged.
    func reconcile() async {
        if reconcileTask == nil {
            reconcileTask = Task {
                await loadRegistryIfNeeded()
                for model in catalog {
                    await reconcileFiles(of: model)
                }
                await refreshStorageUsage()
                hasReconciled = true
                reconcileTask = nil
            }
        }
        await reconcileTask?.value
    }

    /// Loaded once: from then on this object is the authority, and a later load could undo a finished install.
    private func loadRegistryIfNeeded() async {
        guard !hasLoadedRegistry else {
            return
        }
        do {
            let stored = try await registryStore.load()
            registry.artifactSizes.merge(stored.artifactSizes) { current, _ in current }
            registry.installations.merge(stored.installations) { current, _ in current }
            hasLoadedRegistry = true
        } catch {
            Self.logger.error("Could not read the model registry: \(String(describing: error))")
            storageFailure = error as? ModelManagementError ?? .storageAccessDenied(detail: error.localizedDescription)
        }
    }

    private func reconcileFiles(of model: Model) async {
        let id = model.id
        guard !state(of: id).isInstalling, state(of: id) != .removing else {
            return
        }
        let generation = generations[id, default: 0]
        let next = await workflow.reconciledState(
            of: model,
            installation: registry.installations[id],
            current: state(of: id)
        )
        guard generations[id, default: 0] == generation else {
            return
        }
        if next == .notInstalled, registry.installations.removeValue(forKey: id) != nil {
            await saveRegistry()
        }
        guard generations[id, default: 0] == generation, state(of: id) != next else {
            return
        }
        setState(next, for: id)
    }

    // MARK: - Catalog

    /// Updates what is available and how large it is, once per launch and only when Settings asks. Failing changes
    /// nothing about installed models and leaves the saved sizes in place.
    func refreshCatalog() async {
        guard !isRecordingActive, !hasRefreshedCatalog else {
            return
        }
        if catalogRefreshTask == nil {
            catalogRefreshTask = Task {
                await loadRegistryIfNeeded()
                let snapshot = await workflow.fetchCatalog(of: catalog)
                supportedModelIDs = snapshot.supportedIDs
                registry.artifactSizes.merge(snapshot.sizes) { _, fetched in fetched }
                isCatalogOutdated = snapshot.isOutdated
                hasRefreshedCatalog = !snapshot.isOutdated
                await saveRegistry()
                catalogRefreshTask = nil
            }
        }
        await catalogRefreshTask?.value
    }

    func refreshStorageUsage() async {
        storageUsageBytes = await provider.diskUsage()
    }

    // MARK: - Helpers

    func saveRegistry() async {
        do {
            try await registryStore.save(registry)
            storageFailure = nil
        } catch {
            // Next launch treats the files as an unfinished download, and Retry confirms them without downloading.
            Self.logger.error("Could not save the model registry: \(String(describing: error))")
            storageFailure = error as? ModelManagementError ?? .storageAccessDenied(detail: error.localizedDescription)
        }
    }

    func setState(_ next: ModelInstallState, for id: Model.ID) {
        let current = state(of: id)
        guard current.allowsTransition(to: next) else {
            assertionFailure("Invalid model transition from \(current) to \(next)")
            Self.logger.fault("Invalid model transition for \(id, privacy: .public)")
            return
        }
        states[id] = next
        generations[id, default: 0] += 1
    }

    /// Generic types cannot hold static stored properties.
    static var logger: Logger {
        Logger(category: "Models")
    }
}

typealias SpeechModelManager = ModelManager<SpeechModel>
typealias LanguageModelManager = ModelManager<LanguageModel>
typealias EmbeddingModelManager = ModelManager<EmbeddingModel>

extension ModelManager where Model == SpeechModel {
    convenience init(
        catalog: [SpeechModel] = SpeechModelCatalog.curated,
        provider: any ModelFileProviding<SpeechModel>,
        registryStore: any ModelRegistryStore,
        settings: any SettingsRepository,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.init(catalog: catalog, provider: provider, registryStore: registryStore, selection: settings, now: now)
    }
}
