import Foundation
import os

/// The steps of bringing a model onto the disk and comparing what is there with what should be. It keeps no state: all
/// of that belongs to `ModelManager`, which decides what a result means for the model.
struct ModelFileWorkflow<Model: InstallableModel>: Sendable {
    enum InstallEvent: Sendable {
        case progress(ModelDownloadProgress)
        case verifying
    }

    struct InstalledFiles: Sendable {
        let artifact: ModelArtifact
        let sizeBytes: Int64
    }

    struct CatalogSnapshot: Sendable {
        let supportedIDs: Set<Model.ID>
        let sizes: [Model.ID: Int64]
        /// Some sizes could not be fetched, so what was saved earlier remains in use.
        let isOutdated: Bool
    }

    let provider: any ModelFileProviding<Model>

    /// Everything from checking the source to verified files. Cancelling stops it wherever it is, leaving partial files
    /// for the caller to keep or discard. Throws `ModelManagementError` or `CancellationError`.
    func install(
        _ model: Model,
        onEvent: @escaping @Sendable (InstallEvent) -> Void
    ) async throws -> InstalledFiles {
        try Task.checkCancellation()
        let artifact = try await provider.fetchArtifact(of: model)
        try await checkDiskSpace(for: artifact, of: model)
        try await provider.download(model, artifact: artifact) { onEvent(.progress($0)) }
        try Task.checkCancellation()
        onEvent(.verifying)
        let sizeBytes = try await provider.verify(model, against: artifact, depth: .full)
        return InstalledFiles(artifact: artifact, sizeBytes: sizeBytes)
    }

    private func checkDiskSpace(for artifact: ModelArtifact, of model: Model) async throws {
        let downloaded = await provider.inspect(model).bytes
        let required = artifact.requiredFreeBytes(alreadyDownloaded: downloaded)
        let available = try await provider.availableCapacity()
        guard available >= required else {
            throw ModelManagementError.insufficientDiskSpace(requiredBytes: required, availableBytes: available)
        }
    }

    /// What the disk says about a model. Only reads metadata and sizes, so it is cheap enough for every launch.
    func reconciledState(
        of model: Model,
        installation: ModelInstallation?,
        current: ModelInstallState
    ) async -> ModelInstallState {
        guard let installation else {
            let inspection = await provider.inspect(model)
            // A reported failure stays until the user acts on it, unless what it describes has gone away.
            if case .failed(let failure) = current, inspection.hasFiles || failure != .interruptedDownload {
                return .failed(failure)
            }
            return inspection.hasFiles ? .failed(.interruptedDownload) : .notInstalled
        }
        do {
            let sizeBytes = try await provider.verify(model, against: installation.artifact, depth: .quick)
            return .installed(sizeBytes: sizeBytes)
        } catch ModelManagementError.verificationFailed {
            // Files that vanished entirely were removed on purpose; a partial set is damage worth reporting.
            return await provider.inspect(model).hasFiles ? .failed(.damagedInstallation) : .notInstalled
        } catch {
            return .failed(error as? ModelManagementError ?? .damagedInstallation)
        }
    }

    /// What this Mac supports and how large each model is, from the repository when it can be reached.
    func fetchCatalog(of catalog: [Model]) async -> CatalogSnapshot {
        let supportedIDs = await provider.fetchSupportedModelIDs()
        var sizes: [Model.ID: Int64] = [:]
        var isOutdated = false
        for model in catalog where supportedIDs.contains(model.id) {
            do {
                sizes[model.id] = try await provider.fetchArtifact(of: model).totalBytes
            } catch ModelManagementError.modelUnavailable {
                Self.logger.notice("The repository no longer has \(model.id, privacy: .public)")
            } catch {
                Self.logger.notice("Could not refresh \(model.id, privacy: .public): \(String(describing: error))")
                isOutdated = true
            }
        }
        return CatalogSnapshot(supportedIDs: supportedIDs, sizes: sizes, isOutdated: isOutdated)
    }

    /// Generic types cannot hold static stored properties.
    private static var logger: Logger {
        Logger(category: "Models")
    }
}
