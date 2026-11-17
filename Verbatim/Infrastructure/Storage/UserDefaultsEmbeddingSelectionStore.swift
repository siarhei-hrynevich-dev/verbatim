import Foundation

/// Remembers which embedding model is selected.
struct UserDefaultsEmbeddingSelectionStore: ModelSelectionStore {
    private static let selectedModelIDKey = "search.selectedModelID"

    /// UserDefaults is documented as thread-safe, but is not marked Sendable.
    nonisolated(unsafe) let defaults: UserDefaults

    func loadSelectedModelID() -> String? {
        defaults.string(forKey: Self.selectedModelIDKey)
    }

    func saveSelectedModelID(_ id: String?) {
        defaults.set(id, forKey: Self.selectedModelIDKey)
    }
}
