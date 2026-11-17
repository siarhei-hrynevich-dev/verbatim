import Foundation

/// Transcript files beside a recording's media. Each is written to a temporary file in the same folder and moved into
/// place, so a failure leaves the previous file whole. The media is never touched.
struct FileTranscriptStore: TranscriptFileStore {
    func writeFiles(of transcript: Transcript, besideMediaAt mediaURL: URL) async throws {
        let folder = mediaURL.deletingLastPathComponent()
        for format in TranscriptFormat.allCases {
            let file = folder.appending(path: format.fileName, directoryHint: .notDirectory)
            try format.rendered(transcript).write(to: file, options: .atomic)
        }
    }

    func availableBytes(besideMediaAt mediaURL: URL) async -> Int64? {
        let values = try? mediaURL.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
