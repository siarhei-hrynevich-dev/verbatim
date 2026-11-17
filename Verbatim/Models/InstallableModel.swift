import Foundation

/// A model the app can download, verify, select and remove: a speech model or a language model. Each kind keeps its
/// own catalog, storage folder, registry and selection; `ModelManager` runs the same install lifecycle for all of them.
protocol InstallableModel: Identifiable, Equatable, Sendable where ID == String {
    /// Where an installed model's files are, as the engine that loads them needs it. Resolving loads nothing.
    associatedtype Resolved: Equatable, Sendable

    var name: String { get }
    var summary: String { get }
    /// One line under the summary, such as the languages a model knows.
    var detail: String { get }
    /// Files that several models of a catalog can share, such as a tokenizer. They are removed only with the last model
    /// that uses them. `nil` when a model's files are all its own.
    var sharedFilesKey: String? { get }

    /// The model suggested when none is installed. Offered, never downloaded automatically.
    static func recommended(from catalog: [Self], supportedIDs: Set<ID>) -> Self?
}

/// A resolved model held in use. It cannot be removed until the lease is released.
struct ModelLease<Model: InstallableModel>: Identifiable, Equatable, Sendable {
    let id: UUID
    let model: Model.Resolved
}

/// The files that make up an installed model, as published by its repository.
struct ModelArtifact: Codable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable {
        /// Relative to the model storage folder.
        let path: String
        let sizeBytes: Int64
        /// Present for large files, whose content the repository hashes.
        let sha256: String?
    }

    let files: [File]

    var totalBytes: Int64 {
        files.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Space a download needs, on top of what is already on disk, with room left for the recordings on the same volume.
    func requiredFreeBytes(alreadyDownloaded: Int64) -> Int64 {
        max(0, totalBytes - alreadyDownloaded) + Self.freeSpaceMarginBytes
    }

    private static let freeSpaceMarginBytes: Int64 = 500_000_000
}

/// How much of a model has reached the disk.
struct ModelDownloadProgress: Equatable, Sendable {
    let completedBytes: Int64
    let totalBytes: Int64

    /// From 0 to 1. Leftovers of an earlier download can briefly exceed the total, so it is clamped.
    var fraction: Double {
        guard totalBytes > 0 else {
            return 0
        }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }
}

/// How thoroughly installed files are checked.
enum ModelVerificationDepth: Equatable, Sendable {
    /// Existence and sizes: cheap enough for every launch.
    case quick
    /// Also hashes file content, after a download.
    case full
}

/// What is on disk for a model, regardless of whether it is complete.
struct ModelDiskInspection: Equatable, Sendable {
    let hasFiles: Bool
    let bytes: Int64

    static let empty = ModelDiskInspection(hasFiles: false, bytes: 0)
}

/// A completed, verified installation. The artifact is what later launches compare the disk against. It only ever
/// describes files to check: paths to delete are derived from the catalog, never read from this record.
struct ModelInstallation: Codable, Equatable, Sendable {
    let installedAt: Date
    let artifact: ModelArtifact
}

/// The persisted knowledge about models: a statement to reconcile with the disk, which remains the authority.
struct ModelRegistry: Codable, Equatable, Sendable {
    var installations: [String: ModelInstallation] = [:]
    /// The last known download sizes, so the catalog shows them offline.
    var artifactSizes: [String: Int64] = [:]
}

/// Why a model operation failed. User-facing wording belongs to Presentation.
enum ModelManagementError: Error, Equatable, Sendable {
    case noNetwork
    case downloadFailed(detail: String)
    case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64)
    /// The repository does not have this model.
    case modelUnavailable
    case unsupportedOnThisMac
    case verificationFailed(detail: String)
    /// Files remain from a download that never finished, such as when the app quit.
    case interruptedDownload
    /// An installed model's files no longer match what was installed.
    case damagedInstallation
    case storageAccessDenied(detail: String)
    case removalFailed(detail: String)
    case modelInUse
    case modelNotInstalled
    case noModelSelected
    case selectedModelUnavailable(String)
}

/// Installation state of a model. Transitions are explicit, so an operation cannot end up somewhere it should not.
enum ModelInstallState: Equatable, Sendable {
    case notInstalled
    /// `nil` until the first measurement.
    case downloading(ModelDownloadProgress?)
    /// Held back by a recording, and continued when it ends.
    case waitingForRecording(ModelDownloadProgress?)
    case verifying
    case installed(sizeBytes: Int64)
    case removing
    case failed(ModelManagementError)

    var isInstalled: Bool {
        if case .installed = self {
            return true
        }
        return false
    }

    /// Work is running or scheduled; only cancelling applies.
    var isInstalling: Bool {
        switch self {
        case .downloading, .waitingForRecording, .verifying: true
        case .notInstalled, .installed, .removing, .failed: false
        }
    }

    /// Rejecting anything else is what prevents duplicate downloads of a model.
    var acceptsDownload: Bool {
        switch self {
        case .notInstalled, .failed: true
        case .downloading, .waitingForRecording, .verifying, .installed, .removing: false
        }
    }

    var acceptsRemoval: Bool {
        switch self {
        case .installed, .failed: true
        case .notInstalled, .downloading, .waitingForRecording, .verifying, .removing: false
        }
    }

    func allowsTransition(to next: ModelInstallState) -> Bool {
        switch (self, next) {
        case (.notInstalled, .downloading), (.notInstalled, .waitingForRecording), (.notInstalled, .installed),
            (.notInstalled, .failed), (.notInstalled, .notInstalled):
            true
        case (.downloading, .downloading), (.downloading, .verifying), (.downloading, .waitingForRecording),
            (.downloading, .failed), (.downloading, .notInstalled):
            true
        case (.waitingForRecording, .downloading), (.waitingForRecording, .notInstalled):
            true
        case (.verifying, .installed), (.verifying, .waitingForRecording), (.verifying, .failed),
            (.verifying, .notInstalled):
            true
        case (.installed, .installed), (.installed, .removing), (.installed, .failed), (.installed, .notInstalled):
            true
        case (.removing, .notInstalled), (.removing, .installed), (.removing, .failed):
            true
        case (.failed, .downloading), (.failed, .waitingForRecording), (.failed, .removing), (.failed, .installed),
            (.failed, .notInstalled), (.failed, .failed):
            true
        default:
            false
        }
    }
}
