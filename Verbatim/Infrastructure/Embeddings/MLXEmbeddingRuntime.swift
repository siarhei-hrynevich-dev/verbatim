import Foundation
import MLX
import MLXEmbedders
import MLXLMCommon

/// Loads installed embedding models with MLX, from their folder alone, so loading can never reach the network. MLX
/// types stay inside this file.
struct MLXEmbeddingRuntime: LocalEmbeddingRuntime {
    func loadEmbedder(for model: ResolvedEmbeddingModel) async throws -> any TextEmbedder {
        let container = try await EmbedderModelFactory.shared.loadContainer(
            from: model.folder,
            using: TransformersTokenizerLoader()
        )
        return MLXTextEmbedder(container: container, model: model)
    }

    /// Model weights go when the last embedder does; this returns the buffers MLX keeps cached for reuse.
    func releaseMemory() async {
        Memory.clearCache()
    }
}

/// One loaded model. Inference runs on the container's own isolation, one text at a time: chunks are short, and without
/// padding the pooling of every model family is exact.
private struct MLXTextEmbedder: TextEmbedder {
    let container: EmbedderModelContainer
    let model: ResolvedEmbeddingModel

    func embed(_ texts: [String], as role: EmbeddingRole) async throws -> [[Float]] {
        let prefix =
            switch role {
            case .query: model.queryPrefix
            case .passage: model.passagePrefix
            }
        var vectors: [[Float]] = []
        for text in texts {
            try Task.checkCancellation()
            vectors.append(try await embed(prefix + text))
        }
        return vectors
    }

    private func embed(_ text: String) async throws -> [Float] {
        let maxTokens = model.maxInputTokens
        let dimensions = model.space.dimensions
        let vector = await container.perform { context in
            let tokens = Self.truncated(context.tokenizer.encode(text: text, addSpecialTokens: true), to: maxTokens)
            let input = MLXArray(tokens.map(Int32.init)).expandedDimensions(axis: 0)
            let output = context.model(
                input,
                positionIds: nil,
                tokenTypeIds: MLXArray.zeros(like: input),
                attentionMask: nil
            )
            // Normalized to length 1, so that a dot product is the cosine similarity.
            let pooled = context.pooling(output, normalize: true, applyLayerNorm: false)
            pooled.eval()
            return pooled.reshaped(-1).asArray(Float.self)
        }
        guard vector.count == dimensions, vector.allSatisfy(\.isFinite) else {
            throw IndexingFailure.embeddingFailed(detail: "The model returned an unusable vector")
        }
        return vector
    }

    /// Keeps the beginning and the closing special token, as the model was trained to see a cut text.
    private static func truncated(_ tokens: [Int], to limit: Int) -> [Int] {
        guard tokens.count > limit, limit > 1, let last = tokens.last else {
            return tokens
        }
        return Array(tokens.prefix(limit - 1)) + [last]
    }
}
