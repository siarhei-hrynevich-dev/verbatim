import Foundation

/// A model that turns text into a vector for searching recordings by meaning. Its files come from a Hugging Face
/// repository at a fixed commit, like a language model's.
struct EmbeddingModel: HubHostedModel {
    typealias Resolved = ResolvedEmbeddingModel

    /// The app's own name for the model, used as its folder name and recorded with every vector it makes.
    let id: String
    let name: String
    let summary: String
    let detail: String
    let repository: String
    let revision: String
    let minimumMemoryBytes: UInt64
    /// The length of each vector.
    let dimensions: Int
    /// Tokens the model reads at most; longer text is cut. Search chunks are sized to stay well within it.
    let maxInputTokens: Int
    /// Written before a search query, as the model was trained to see it.
    let queryPrefix: String
    /// Written before indexed text.
    let passagePrefix: String

    /// What the vectors this model makes are comparable with.
    var space: EmbeddingSpace {
        EmbeddingSpace(modelID: id, revision: revision, dimensions: dimensions)
    }

    var sharedFilesKey: String? {
        nil
    }

    static func recommended(from catalog: [EmbeddingModel], supportedIDs: Set<ID>) -> EmbeddingModel? {
        catalog.first { supportedIDs.contains($0.id) }
    }

    func resolved(in folder: URL) -> ResolvedEmbeddingModel {
        ResolvedEmbeddingModel(
            folder: folder,
            space: space,
            maxInputTokens: maxInputTokens,
            queryPrefix: queryPrefix,
            passagePrefix: passagePrefix
        )
    }
}

/// Where an installed embedding model is, and how to use it. Resolving loads nothing.
struct ResolvedEmbeddingModel: Equatable, Sendable {
    let folder: URL
    /// What the vectors it makes are comparable with.
    let space: EmbeddingSpace
    let maxInputTokens: Int
    let queryPrefix: String
    let passagePrefix: String
}

typealias EmbeddingModelLease = ModelLease<EmbeddingModel>

/// The embedding models Verbatim offers: multilingual, so a question in one language finds speech in another,
/// permissively licensed, and of an architecture the MLX engine in use loads. Revisions are pinned to checked commits.
enum EmbeddingModelCatalog {
    static let curated = [
        EmbeddingModel(
            id: "multilingual-e5-small",
            name: "Multilingual E5 Small",
            summary: "Fast and light. Indexes an hour of speech in seconds.",
            detail: "100 languages · MIT",
            repository: "intfloat/multilingual-e5-small",
            revision: "614241f622f53c4eeff9890bdc4f31cfecc418b3",
            minimumMemoryBytes: 8 * gibibyte,
            dimensions: 384,
            maxInputTokens: 512,
            queryPrefix: "query: ",
            passagePrefix: "passage: "
        ),
        EmbeddingModel(
            id: "multilingual-e5-base",
            name: "Multilingual E5 Base",
            summary: "Finds what was meant more reliably, at about twice the size and time.",
            detail: "100 languages · MIT",
            repository: "intfloat/multilingual-e5-base",
            revision: "d128750597153bb5987e10b1c3493a34e5a4502a",
            minimumMemoryBytes: 8 * gibibyte,
            dimensions: 768,
            maxInputTokens: 512,
            queryPrefix: "query: ",
            passagePrefix: "passage: "
        )
    ]

    private static let gibibyte: UInt64 = 1_024 * 1_024 * 1_024
}
