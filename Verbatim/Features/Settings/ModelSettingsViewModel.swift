import Foundation
import Observation

/// What the AI Models tab shows of one kind of model, and the user's actions on it. Downloads and files belong to
/// `ModelManager`, which outlives this object and the window.
@MainActor
@Observable
final class ModelSettingsViewModel<Model: InstallableModel> {
    /// One model as the catalog shows it.
    struct Row: Identifiable, Equatable {
        let model: Model
        let state: ModelInstallState
        /// `nil` until a size is known.
        let sizeBytes: Int64?
        let isSelected: Bool
        let isSupported: Bool

        var id: Model.ID {
            model.id
        }
    }

    /// A removal waiting to be confirmed.
    struct RemovalRequest: Identifiable, Equatable {
        let model: Model
        let reclaimedBytes: Int64?
        let isSelected: Bool

        var id: Model.ID {
            model.id
        }
    }

    /// What needs attention above the catalog. Selecting or downloading is left to the user.
    enum Notice: Equatable {
        case noModelInstalled(recommended: Model?)
        case noModelSelected
        case selectedModelUnavailable(Model)
    }

    var removalRequest: RemovalRequest?
    /// A failed action that has no place in a row.
    var actionIssue: ModelIssue?

    let manager: ModelManager<Model>
    private let systemActions: any SystemActions

    init(manager: ModelManager<Model>, systemActions: any SystemActions) {
        self.manager = manager
        self.systemActions = systemActions
    }

    // MARK: - State

    var rows: [Row] {
        manager.catalog.map { model in
            Row(
                model: model,
                state: manager.state(of: model.id),
                sizeBytes: manager.sizeBytes(of: model.id),
                isSelected: manager.selectedModelID == model.id && manager.state(of: model.id).isInstalled,
                isSupported: manager.supportedModelIDs.contains(model.id)
            )
        }
    }

    var notice: Notice? {
        guard manager.hasReconciled else {
            return nil
        }
        if case .unavailable(let model) = manager.selectionStatus {
            return .selectedModelUnavailable(model)
        }
        let states = manager.catalog.map { manager.state(of: $0.id) }
        if !states.contains(where: \.isInstalled) {
            // A model on its way is answer enough; the row shows how it is going.
            return states.contains(where: \.isInstalling)
                ? nil : .noModelInstalled(recommended: manager.recommendedModel)
        }
        return manager.selectionStatus == .none ? .noModelSelected : nil
    }

    var storageUsageBytes: Int64 {
        manager.storageUsageBytes
    }

    var isCatalogOutdated: Bool {
        manager.isCatalogOutdated
    }

    var isRecordingActive: Bool {
        manager.isRecordingActive
    }

    var storageIssue: ModelIssue? {
        manager.storageFailure.map { ModelIssue($0) }
    }

    /// Installed models that are not selected, as candidates for freeing space.
    var unusedModels: [Row] {
        rows.filter { $0.state.isInstalled && !$0.isSelected }
    }

    // MARK: - Actions

    /// Checks files against what is recorded, and refreshes the catalog when the repository can be reached. Reads
    /// metadata only; no model is loaded.
    func refresh() async {
        await manager.reconcile()
        await manager.refreshCatalog()
    }

    func download(_ id: Model.ID) {
        manager.download(id)
    }

    func cancelDownload(_ id: Model.ID) {
        manager.cancelDownload(id)
    }

    func select(_ id: Model.ID) {
        do {
            try manager.select(id)
        } catch {
            actionIssue = ModelIssue(error)
        }
    }

    /// Asks before removing. Failed downloads hold nothing worth a question, so they go straight away.
    func requestRemoval(of id: Model.ID) {
        guard let row = rows.first(where: { $0.id == id }), row.state.acceptsRemoval else {
            return
        }
        guard row.state.isInstalled else {
            remove(id)
            return
        }
        removalRequest = RemovalRequest(model: row.model, reclaimedBytes: row.sizeBytes, isSelected: row.isSelected)
    }

    func confirmRemoval() {
        guard let request = removalRequest else {
            return
        }
        removalRequest = nil
        remove(request.model.id)
    }

    func cancelRemoval() {
        removalRequest = nil
    }

    private func remove(_ id: Model.ID) {
        Task {
            do {
                try await manager.remove(id)
            } catch {
                actionIssue = ModelIssue(error)
            }
        }
    }

    func showModelsInFinder() {
        let location = manager.storageLocation
        Task {
            await systemActions.openInFinder(location)
        }
    }

    func dismissIssue() {
        actionIssue = nil
    }
}
