import Foundation

/// A Whisper speech recognition model that can be installed on this Mac.
struct SpeechModel: InstallableModel {
    typealias Resolved = ResolvedSpeechModel

    /// The exact variant name in WhisperKit's model repository.
    let id: String
    let name: String
    let summary: String
    let languageSupport: String
    /// The Hub repository holding this model's tokenizer. WhisperKit fetches tokenizers separately from model weights,
    /// and several models can share one.
    let tokenizerRepository: String

    var detail: String {
        languageSupport
    }

    /// Models of the same size share a tokenizer.
    var sharedFilesKey: String? {
        tokenizerRepository
    }

    static func recommended(from catalog: [SpeechModel], supportedIDs: Set<ID>) -> SpeechModel? {
        SpeechModelCatalog.recommended(from: catalog, supportedIDs: supportedIDs)
    }
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

/// The contract for a transcription engine: where an installed model is, without anything having been loaded.
struct ResolvedSpeechModel: Equatable, Sendable {
    let id: SpeechModel.ID
    /// Pass as `WhisperKitConfig.modelFolder`.
    let modelFolder: URL
    /// Pass as `WhisperKitConfig.tokenizerFolder`, with downloads off, so nothing touches the network.
    let tokenizerBase: URL
}

typealias SpeechModelLease = ModelLease<SpeechModel>
