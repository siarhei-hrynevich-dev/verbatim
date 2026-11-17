import Foundation

/// A language model that runs on this Mac and writes summaries of transcripts. Its files come from a Hugging Face
/// repository at a fixed commit, so a change in the repository can neither change nor break an installed model.
struct LanguageModel: HubHostedModel {
    typealias Resolved = ResolvedLanguageModel

    /// The app's own name for the model, used as its folder name.
    let id: String
    let name: String
    let summary: String
    let detail: String
    /// The Hugging Face repository, as `owner/name`.
    let repository: String
    /// The commit the files are downloaded from.
    let revision: String
    /// Unified memory below which the model is shown as not supported on this Mac.
    let minimumMemoryBytes: UInt64
    /// Tokens the model is asked to attend to at once. Batches and their notes stay within it.
    let contextTokens: Int
    /// Hybrid reasoning models think aloud before answering unless asked not to; summaries ask them not to.
    let disablesThinking: Bool
    /// Settings tuned for summarizing with this model, and what Reset returns to.
    let preset: SummarySettings

    var sharedFilesKey: String? {
        nil
    }

    static func recommended(from catalog: [LanguageModel], supportedIDs: Set<ID>) -> LanguageModel? {
        LanguageModelCatalog.recommended(from: catalog, supportedIDs: supportedIDs)
    }

    func resolved(in folder: URL) -> ResolvedLanguageModel {
        ResolvedLanguageModel(id: id, folder: folder, disablesThinking: disablesThinking)
    }
}

/// Where an installed language model is, for the engine that loads it. Resolving loads nothing.
struct ResolvedLanguageModel: Equatable, Sendable {
    let id: LanguageModel.ID
    /// Holds the configuration, weights and tokenizer, ready to load without the network.
    let folder: URL
    let disablesThinking: Bool
}

typealias LanguageModelLease = ModelLease<LanguageModel>

/// The language models Verbatim offers: multilingual, permissively licensed, and of an architecture the MLX engine in
/// use loads. Revisions are pinned to the commits that were checked.
enum LanguageModelCatalog {
    static let curated = [
        LanguageModel(
            id: "qwen3-1.7b-4bit",
            name: "Qwen3 1.7B",
            summary: "Fast and light. Fine for short recordings and Macs with 8 GB of memory.",
            detail: "Multilingual · Apache 2.0",
            repository: "mlx-community/Qwen3-1.7B-4bit",
            revision: "3b1b1768f8f8cf8351c712464f906e86c2b8269e",
            minimumMemoryBytes: 8 * gibibyte,
            contextTokens: 32_768,
            disablesThinking: true,
            preset: SummarySettings(
                batchTokens: 3_000,
                batchNoteTokens: 300,
                summaryTokens: 500,
                temperature: 0.3,
                topP: 0.8,
                topK: 20,
                repetitionPenalty: 1.1
            )
        ),
        LanguageModel(
            id: "qwen3-4b-instruct-2507-4bit",
            name: "Qwen3 4B Instruct",
            summary: "Balanced quality and speed. Follows the transcript closely.",
            detail: "Multilingual · Apache 2.0",
            repository: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
            revision: "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b",
            minimumMemoryBytes: 8 * gibibyte,
            contextTokens: 32_768,
            disablesThinking: false,
            preset: SummarySettings(
                batchTokens: 6_000,
                batchNoteTokens: 400,
                summaryTokens: 600,
                temperature: 0.3,
                topP: 0.8,
                topK: 20,
                repetitionPenalty: 1.05
            )
        ),
        LanguageModel(
            id: "qwen3-30b-a3b-instruct-2507-4bit",
            name: "Qwen3 30B-A3B Instruct",
            summary: "The most capable, and still quick: only part of it runs for each word. Needs a lot of memory.",
            detail: "Multilingual · Apache 2.0 · needs 32 GB of memory",
            repository: "mlx-community/Qwen3-30B-A3B-Instruct-2507-4bit",
            revision: "e9675aa3ca5f900ccef55267914466d55ab325fa",
            minimumMemoryBytes: 32 * gibibyte,
            contextTokens: 32_768,
            disablesThinking: false,
            preset: SummarySettings(
                batchTokens: 8_000,
                batchNoteTokens: 500,
                summaryTokens: 800,
                temperature: 0.3,
                topP: 0.8,
                topK: 20,
                repetitionPenalty: 1.05
            )
        )
    ]

    /// The best summaries first, where the Mac supports them.
    private static let recommendationOrder = [
        "qwen3-4b-instruct-2507-4bit",
        "qwen3-1.7b-4bit"
    ]

    static func recommended(from catalog: [LanguageModel], supportedIDs: Set<LanguageModel.ID>) -> LanguageModel? {
        let supported = catalog.filter { supportedIDs.contains($0.id) }
        for id in recommendationOrder {
            if let model = supported.first(where: { $0.id == id }) {
                return model
            }
        }
        return supported.first
    }

    private static let gibibyte: UInt64 = 1_024 * 1_024 * 1_024
}
