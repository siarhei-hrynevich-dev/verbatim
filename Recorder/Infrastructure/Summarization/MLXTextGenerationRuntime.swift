import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Loads installed language models with MLX, from their folder alone: no downloader is given, so loading can never
/// reach the network. The only place that imports MLX; nothing outside sees its types.
struct MLXTextGenerationRuntime: LocalTextGenerationRuntime {
    func loadGenerator(for model: ResolvedLanguageModel) async throws -> any TextGenerator {
        let container = try await LLMModelFactory.shared.loadContainer(
            from: model.folder,
            using: TransformersTokenizerLoader()
        )
        return MLXTextGenerator(container: container, disablesThinking: model.disablesThinking)
    }

    /// Model weights go when the last generator does; this returns the buffers MLX keeps cached for reuse.
    func releaseMemory() async {
        Memory.clearCache()
    }
}

/// One loaded model. Generation runs on MLX's own isolation inside the container.
private struct MLXTextGenerator: TextGenerator {
    let container: ModelContainer
    let disablesThinking: Bool

    func tokenCount(of text: String) async throws -> Int {
        await container.encode(text).count
    }

    func generate(_ messages: [TextGenerationMessage], parameters: TextGenerationParameters) async throws -> String {
        let chat: [Chat.Message] = messages.map { message in
            switch message.role {
            case .system: .system(message.content)
            case .user: .user(message.content)
            }
        }
        // Read by the chat templates of hybrid reasoning models; others ignore it.
        let context: [String: any Sendable]? = disablesThinking ? ["enable_thinking": false] : nil
        let input = try await container.prepare(input: UserInput(chat: chat, additionalContext: context))
        let stream = try await container.generate(input: input, parameters: Self.mlxParameters(from: parameters))
        var text = ""
        // Leaving the loop ends the stream, which stops generation at the next token.
        for await event in stream {
            try Task.checkCancellation()
            if let chunk = event.chunk {
                text += chunk
            }
        }
        try Task.checkCancellation()
        return text
    }

    private static func mlxParameters(from parameters: TextGenerationParameters) -> GenerateParameters {
        GenerateParameters(
            maxTokens: parameters.maxOutputTokens,
            temperature: Float(parameters.temperature),
            topP: Float(parameters.topP),
            topK: parameters.topK,
            repetitionPenalty: parameters.repetitionPenalty > 1 ? Float(parameters.repetitionPenalty) : nil
        )
    }
}

/// Reads a tokenizer from a model's folder with swift-transformers, which needs no network for local folders.
private struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(upstream: try await AutoTokenizer.from(modelFolder: directory))
    }
}

/// Presents a swift-transformers tokenizer through MLX's tokenizer protocol.
private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    var bosToken: String? {
        upstream.bosToken
    }

    var eosToken: String? {
        upstream.eosToken
    }

    var unknownToken: String? {
        upstream.unknownToken
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
