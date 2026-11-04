import Foundation

/// A Whisper speech recognition model that can be installed on this Mac.
struct SpeechModel: Identifiable, Equatable, Sendable {
    /// The exact variant name in WhisperKit's model repository.
    let id: String
    let name: String
    let summary: String
    let languageSupport: String
    /// The Hub repository holding this model's tokenizer. WhisperKit fetches tokenizers separately from model weights,
    /// and several models can share one.
    let tokenizerRepository: String
}

/// The models Verbatim offers: multilingual, verified against WhisperKit 1.1.1's supported variants and the files in
/// its repository. Availability on a given Mac is still decided by WhisperKit at run time.
enum SpeechModelCatalog {
    static let curated = [
        SpeechModel(
            id: "openai_whisper-tiny",
            name: "Tiny",
            summary: "Fastest. Fine for clear speech in a quiet room.",
            languageSupport: "Multilingual · 99 languages",
            tokenizerRepository: "openai/whisper-tiny"
        ),
        SpeechModel(
            id: "openai_whisper-base",
            name: "Base",
            summary: "Fast, with fair accuracy for short notes and dictation.",
            languageSupport: "Multilingual · 99 languages",
            tokenizerRepository: "openai/whisper-base"
        ),
        SpeechModel(
            id: "openai_whisper-small",
            name: "Small",
            summary: "Balanced speed and accuracy for most calls.",
            languageSupport: "Multilingual · 99 languages",
            tokenizerRepository: "openai/whisper-small"
        ),
        SpeechModel(
            id: "openai_whisper-large-v3-v20240930_turbo",
            name: "Large v3 Turbo",
            summary: "Close to Large v3 accuracy at several times the speed.",
            languageSupport: "Multilingual · 100 languages",
            // WhisperKit identifies this model as Large v3, so it looks for that tokenizer.
            tokenizerRepository: "openai/whisper-large-v3"
        )
    ]

    /// The most capable model first. WhisperKit's own default for a Mac can be a model outside this catalog.
    private static let recommendationOrder = [
        "openai_whisper-large-v3-v20240930_turbo",
        "openai_whisper-small"
    ]

    /// The model suggested when none is installed. Offered, never downloaded automatically.
    static func recommended(from catalog: [SpeechModel], supportedIDs: Set<SpeechModel.ID>) -> SpeechModel? {
        let supported = catalog.filter { supportedIDs.contains($0.id) }
        for id in recommendationOrder {
            if let model = supported.first(where: { $0.id == id }) {
                return model
            }
        }
        return supported.first
    }
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
    var installations: [SpeechModel.ID: ModelInstallation] = [:]
    /// The last known download sizes, so the catalog shows them offline.
    var artifactSizes: [SpeechModel.ID: Int64] = [:]
}

/// The contract for a transcription engine: where an installed model is, without anything having been loaded.
struct ResolvedSpeechModel: Equatable, Sendable {
    let id: SpeechModel.ID
    /// Pass as `WhisperKitConfig.modelFolder`.
    let modelFolder: URL
    /// Pass as `WhisperKitConfig.tokenizerFolder`, with downloads off, so nothing touches the network.
    let tokenizerBase: URL
}

/// A resolved model held in use. It cannot be removed until the lease is released.
struct ModelLease: Identifiable, Equatable, Sendable {
    let id: UUID
    let model: ResolvedSpeechModel
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
    case selectedModelUnavailable(SpeechModel.ID)
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
