import Foundation

/// One turn of a conversation with a language model.
struct TextGenerationMessage: Equatable, Sendable {
    enum Role: String, Sendable {
        case system
        case user
    }

    let role: Role
    let content: String

    static func system(_ content: String) -> Self {
        Self(role: .system, content: content)
    }

    static func user(_ content: String) -> Self {
        Self(role: .user, content: content)
    }
}

/// How text is sampled, in terms every backend understands.
struct TextGenerationParameters: Equatable, Sendable {
    var maxOutputTokens: Int
    var temperature: Double
    var topP: Double
    /// 0 turns the limit off.
    var topK: Int
    /// 1 turns the penalty off.
    var repetitionPenalty: Double
}

/// A model ready to write text. This is the boundary summarization depends on, and the one to implement for another
/// backend: an MLX model on this Mac today, and equally a local server or a provider's API.
protocol TextGenerator: Sendable {
    /// The tokens a text takes in this model's vocabulary, for fitting batches to its context.
    func tokenCount(of text: String) async throws -> Int
    /// Writes a reply to the conversation. Throws `CancellationError` once cancelled, between generated tokens.
    func generate(_ messages: [TextGenerationMessage], parameters: TextGenerationParameters) async throws -> String
}

/// A generator handed to one job, with what it should be used with. The job gives it back through its provider.
struct TextGenerationSession: Sendable {
    let id: UUID
    /// Recorded with the summary.
    let modelID: String
    let settings: SummarySettings
    let generator: any TextGenerator
}

/// Where summarization gets a generator, and gives it back. For installed models this holds a lease on the files and
/// loads the model; a provider for a server or an API would connect instead, with nothing to install.
@MainActor
protocol TextGenerationProvider: AnyObject {
    /// A model is selected and its files are in place, as far as is known without checking the disk again.
    var hasUsableModel: Bool { get }
    /// Brings model state in line with the disk, so files removed since launch are noticed before they are needed.
    func prepareForUse() async
    /// Throws `SummaryFailure`, or `CancellationError`. Loading can take a while; nothing is switched or downloaded.
    func acquireGenerator() async throws -> TextGenerationSession
    /// Frees what the session held: the model's memory and its lease. Takes only the identifier, so the caller has
    /// already let go of the generator and its memory can actually be returned.
    func release(sessionID: UUID) async
}

/// Loads installed language models into memory. Implemented with MLX.
protocol LocalTextGenerationRuntime: Sendable {
    /// Throws when the files cannot be loaded. Never downloads anything.
    func loadGenerator(for model: ResolvedLanguageModel) async throws -> any TextGenerator
    /// Returns memory the engine keeps cached after its models are gone. Safe to call with nothing loaded.
    func releaseMemory() async
}

/// Stores finished summaries. Throws `LibraryError`.
protocol SummaryRepository: Sendable {
    func summary(for recordingID: UUID) async throws -> TranscriptSummary?
    /// Swaps in a complete summary with its parts in one transaction. Throws `LibraryError.recordingNotFound` when the
    /// recording has left the Library.
    func replaceSummary(_ summary: TranscriptSummary) async throws
    func deleteSummary(for recordingID: UUID) async throws
    /// Forgets summaries of recordings no longer in the Library, which stay until then so that Undo brings them back.
    func purgeOrphans() async throws
}

/// The selected language model, the language summaries are written in, and the summary settings the user changed for
/// each model.
protocol SummarySettingsRepository: ModelSelectionStore {
    /// `nil` until one is chosen.
    func loadLanguageCode() -> String?
    func saveLanguageCode(_ code: String)
    func loadCustomSettings() -> [LanguageModel.ID: SummarySettings]
    func saveCustomSettings(_ settings: [LanguageModel.ID: SummarySettings])
}
