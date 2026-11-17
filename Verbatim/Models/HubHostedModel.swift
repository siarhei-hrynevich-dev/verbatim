import Foundation

/// A model whose files come from a Hugging Face repository at a fixed commit and load from their folder alone, so a
/// change in the repository can neither change nor break an installed model. Language and embedding models are both.
protocol HubHostedModel: InstallableModel {
    /// The Hugging Face repository, as `owner/name`.
    var repository: String { get }
    /// The commit the files are downloaded from.
    var revision: String { get }
    /// Unified memory below which the model is shown as not supported on this Mac.
    var minimumMemoryBytes: UInt64 { get }

    /// Where the installed model is, for the engine that loads it. Resolving loads nothing.
    func resolved(in folder: URL) -> Resolved
}
