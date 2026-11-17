import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Loads installed language models with MLX, from their folder alone: no downloader is given, so loading can never
/// reach the network. MLX types stay inside this file and the embedding runtime.
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
