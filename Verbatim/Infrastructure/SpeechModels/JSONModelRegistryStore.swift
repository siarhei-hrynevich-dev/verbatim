import Foundation
import OSLog

/// Keeps the model registry as a JSON file beside the models it describes. A file that cannot be understood counts as
/// empty: models then show as unfinished downloads, and Retry confirms complete files without downloading them again.
actor JSONModelRegistryStore: ModelRegistryStore {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func defaultFileURL(in storageLocation: URL) -> URL {
        storageLocation.appending(path: "model-registry.json", directoryHint: .notDirectory)
    }

    func load() throws -> ModelRegistry {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return ModelRegistry()
        } catch {
            throw ModelErrorTranslator.translate(error)
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ModelRegistry.self, from: data)
        } catch {
            Self.logger.fault("The model registry is unreadable and is treated as empty: \(String(describing: error))")
            return ModelRegistry()
        }
    }

    func save(_ registry: ModelRegistry) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(registry).write(to: fileURL, options: .atomic)
        } catch {
            throw ModelErrorTranslator.translate(error)
        }
    }

    private static let logger = Logger(category: "Models")
}
