import Foundation

/// Fixed sample content for the layout-only Settings window: the model catalog and its install states, storage
/// figures, and app version. Model downloads, storage measurement and update checks are not implemented yet;
/// this stands in for what those services will provide.
struct SettingsPreviewData: Sendable {
    let speechModels: [SpeechModel]
    let initialModelStates: [SpeechModel.ID: ModelInstallState]
    let defaultModelID: SpeechModel.ID
    let embeddingModelSummary: String
    let embeddingSizeMegabytes: Int
    let languages: [TranscriptionLanguage]
    let licenses: [ThirdPartyLicense]
    let location: StorageLocation
    /// Stands in for the folder chosen in the Change… folder picker.
    let proposedLocation: StorageLocation
    let recordingCount: Int
    let recordingsMegabytes: Int
    let searchIndexMegabytes: Int
    let previewCacheMegabytes: Int
    let missingRecordingCount: Int
    let version: String
    let build: String
    let lastUpdateCheck: String
    let sourceCodeURL: URL?

    static let sample = SettingsPreviewData(
        speechModels: [
            SpeechModel(
                id: "tiny",
                name: "Tiny",
                sizeMegabytes: 75,
                summary: "Fastest. Fine for clear speech in a quiet room."
            ),
            SpeechModel(
                id: "base",
                name: "Base",
                sizeMegabytes: 142,
                summary: "Fast, with fair accuracy for short notes and dictation."
            ),
            SpeechModel(
                id: "small",
                name: "Small",
                sizeMegabytes: 466,
                summary: "Balanced speed and accuracy for most calls."
            ),
            SpeechModel(
                id: "medium",
                name: "Medium",
                sizeMegabytes: 1_500,
                summary: "More accurate, noticeably slower on long recordings."
            ),
            SpeechModel(
                id: "turbo",
                name: "Large v3 Turbo",
                sizeMegabytes: 1_600,
                summary: "Close to Large v3 accuracy at several times the speed. Recommended."
            ),
            SpeechModel(
                id: "large",
                name: "Large v3",
                sizeMegabytes: 3_100,
                summary: "Most accurate, especially with accents and mixed languages. Slowest."
            )
        ],
        initialModelStates: [
            "tiny": .notInstalled,
            "base": .installed,
            "small": .preparing(progress: 0.3),
            "medium": .downloading(progress: 0.38),
            "turbo": .installed,
            "large": .notInstalled
        ],
        defaultModelID: "turbo",
        embeddingModelSummary: "Multilingual MiniLM L12 · 118 MB · 50+ languages",
        embeddingSizeMegabytes: 118,
        languages: [
            TranscriptionLanguage(code: nil, name: "Auto-detect"),
            TranscriptionLanguage(code: "en", name: "English"),
            TranscriptionLanguage(code: "de", name: "Deutsch"),
            TranscriptionLanguage(code: "es", name: "Español"),
            TranscriptionLanguage(code: "fr", name: "Français"),
            TranscriptionLanguage(code: "ja", name: "日本語"),
            TranscriptionLanguage(code: "uk", name: "Українська")
        ],
        licenses: [
            ThirdPartyLicense(name: "whisper.cpp", license: "MIT"),
            ThirdPartyLicense(name: "OpenAI Whisper models", license: "MIT"),
            ThirdPartyLicense(name: "Multilingual MiniLM L12", license: "Apache 2.0"),
            ThirdPartyLicense(name: "GRDB.swift", license: "MIT"),
            ThirdPartyLicense(name: "Sparkle", license: "MIT"),
            ThirdPartyLicense(name: "swift-collections", license: "Apache 2.0")
        ],
        location: StorageLocation(path: "~/Movies/Verbatim", volumeName: "Macintosh HD", freeBytes: 214_000_000_000),
        proposedLocation: StorageLocation(
            path: "/Volumes/Archive/Verbatim",
            volumeName: "Archive",
            freeBytes: 1_600_000_000_000
        ),
        recordingCount: 48,
        recordingsMegabytes: 38_200,
        searchIndexMegabytes: 186,
        previewCacheMegabytes: 224,
        missingRecordingCount: 2,
        version: "1.2.0",
        build: "142",
        lastUpdateCheck: "09:14",
        sourceCodeURL: URL(string: "https://github.com/verbatim-app/verbatim")
    )
}
