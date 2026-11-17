import SwiftUI
import UniformTypeIdentifiers

/// A rendered transcript on its way through the save panel. Only ever written.
struct TranscriptFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText, .json]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
