import Foundation
import Observation
import os

/// The single owner of speech model state: what is available and installed, which model is selected, and every
/// installation in progress. It outlives the Settings window, so a download continues with the window closed.
///
/// State changes happen synchronously on the main actor before any suspension, so a duplicate request is rejected by
/// the state check. The work itself runs off the main actor in the provider, and no model is ever loaded here.
@MainActor
@Observable
final class ModelManager {
    /// The selected model as far as it can be used right now.
    enum SelectionStatus: Equatable, Sendable {
        case none
        case ready(SpeechModel)
        /// Selected, but its files are gone or damaged. Nothing is switched or downloaded without being asked.
        case unavailable(SpeechModel)
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

    let catalog: [SpeechModel]

    private(set) var states: [SpeechModel.ID: ModelInstallState] = [:]
    private(set) var selectedModelID: SpeechModel.ID?
    private(set) var supportedModelIDs: Set<SpeechModel.ID>
    private(set) var storageUsageBytes: Int64 = 0
    /// The last refresh could not reach the repository, so sizes are the ones saved earlier.
    private(set) var isCatalogOutdated = false
    /// A failure reading or writing the registry, which does not belong to any one model.
    private(set) var storageFailure: ModelManagementError?
    private(set) var hasReconciled = false
    private(set) var isRecordingActive = false
    var registry = ModelRegistry()

    @ObservationIgnored private let provider: any SpeechModelProviding
    @ObservationIgnored let workflow: ModelFileWorkflow
    @ObservationIgnored private let registryStore: any ModelRegistryStore
    @ObservationIgnored private let settings: any SettingsRepository
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored var installs: [SpeechModel.ID: ActiveInstall] = [:]
    @ObservationIgnored var stopReasons: [UUID: StopReason] = [:]
    @ObservationIgnored var filesToDiscardFirst: Set<SpeechModel.ID> = []
    @ObservationIgnored private var leases: [UUID: SpeechModel.ID] = [:]
    /// Advances with each state change, so a slow disk check cannot overwrite what happened during it.
    @ObservationIgnored private var generations: [SpeechModel.ID: Int] = [:]
    @ObservationIgnored private var reconcileTask: Task<Void, Never>?
    @ObservationIgnored private var catalogRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var hasLoadedRegistry = false
    @ObservationIgnored private var hasRefreshedCatalog = false

    init(
        catalog: [SpeechModel] = SpeechModelCatalog.curated,
        provider: any SpeechModelProviding,
        registryStore: any ModelRegistryStore,
        settings: any SettingsRepository,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.catalog = catalog
        self.provider = provider
        workflow = ModelFileWorkflow(provider: provider)
        self.registryStore = registryStore
        self.settings = settings
        self.now = now
        supportedModelIDs = provider.supportedModelIDs()
        selectedModelID = settings.loadSelectedModelID()
    }

    // MARK: - Reading state

    var storageLocation: URL {
        provider.storageLocation
    }

    var recommendedModel: SpeechModel? {
        SpeechModelCatalog.recommended(from: catalog, supportedIDs: supportedModelIDs)
    }

    var selectionStatus: SelectionStatus {
        guard hasReconciled, let selectedModelID, let model = model(withID: selectedModelID) else {
            return .none
        }
        return state(of: selectedModelID).isInstalled ? .ready(model) : .unavailable(model)
    }

    func state(of id: SpeechModel.ID) -> ModelInstallState {
        states[id] ?? .notInstalled
    }

    func model(withID id: SpeechModel.ID) -> SpeechModel? {
        catalog.first { $0.id == id }
    }

    /// The space an installed model takes, or otherwise the last known download size. `nil` until one is known.
    func sizeBytes(of id: SpeechModel.ID) -> Int64? {
        if case .installed(let sizeBytes) = state(of: id) {
            return sizeBytes
        }
        return registry.artifactSizes[id]
    }

    // MARK: - Transcription contract

    /// The selected model's identifier and location, without loading it. Throws `noModelSelected` or
    /// `selectedModelUnavailable`; the caller reports that rather than choosing another model.
    func resolveSelectedModel() throws(ModelManagementError) -> ResolvedSpeechModel {
        guard let selectedModelID, let model = model(withID: selectedModelID) else {
            throw .noModelSelected
        }
        guard state(of: selectedModelID).isInstalled else {
            throw .selectedModelUnavailable(selectedModelID)
        }
        return provider.resolve(model)
    }

    /// Resolves the selected model and protects it from removal until `release(_:)`.
    func acquireSelectedModel() throws(ModelManagementError) -> ModelLease {
        let model = try resolveSelectedModel()
        let lease = ModelLease(id: UUID(), model: model)
        leases[lease.id] = model.id
        return lease
    }

    func release(_ lease: ModelLease) {
        leases[lease.id] = nil
    }

    // MARK: - Selecting

    /// Only an installed, validated model can be selected. Selecting loads nothing.
    func select(_ id: SpeechModel.ID) throws(ModelManagementError) {
        guard state(of: id).isInstalled else {
            throw .modelNotInstalled
        }
        setSelection(id)
    }

    func setSelection(_ id: SpeechModel.ID?) {
        selectedModelID = id
        settings.saveSelectedModelID(id)
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
    func remove(_ id: SpeechModel.ID) async throws(ModelManagementError) {
        guard let model = model(withID: id), state(of: id).acceptsRemoval else {
            throw .modelNotInstalled
        }
        guard !leases.values.contains(id) else {
            throw .modelInUse
        }
        let previous = state(of: id)
        setState(.removing, for: id)
        do {
            try await provider.removeFiles(of: model, includingTokenizer: !isTokenizerShared(by: model))
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

    private func reconcileFiles(of model: SpeechModel) async {
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

    func setState(_ next: ModelInstallState, for id: SpeechModel.ID) {
        let current = state(of: id)
        guard current.allowsTransition(to: next) else {
            assertionFailure("Invalid model transition from \(current) to \(next)")
            Self.logger.fault("Invalid model transition for \(id, privacy: .public)")
            return
        }
        states[id] = next
        generations[id, default: 0] += 1
    }

    static let logger = Logger(subsystem: "dev.local.Recorder", category: "Models")
}
