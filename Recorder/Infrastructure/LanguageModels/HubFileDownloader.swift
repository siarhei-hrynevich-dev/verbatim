import Foundation
import Synchronization

/// Downloads single files from the Hugging Face Hub. Data is written as it arrives into a partial file beside the
/// destination, so progress can be measured on disk and a stopped download continues from where it was with an HTTP
/// range request. The file moves into place only once it has its full length.
struct HubFileDownloader: Sendable {
    let endpoint: String
    private let session: URLSession

    init(endpoint: String, session: URLSession = HubFileDownloader.defaultSession) {
        self.endpoint = endpoint
        self.session = session
    }

    /// Ephemeral, so nothing is cached twice; long timeouts, because weights are gigabytes.
    static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        return URLSession(configuration: configuration)
    }()

    /// Throws `ModelManagementError`, or `CancellationError` once cancelled, which keeps the partial file.
    func download(
        _ repositoryPath: String,
        of repository: String,
        revision: String,
        to destination: URL,
        expectedBytes: Int64
    ) async throws {
        if Self.length(of: destination) == expectedBytes {
            return
        }
        let partial = HubModelFiles.partialFile(for: destination)
        var offset = Self.length(of: partial) ?? 0
        if offset > expectedBytes {
            try? FileManager.default.removeItem(at: partial)
            offset = 0
        }
        if offset < expectedBytes {
            let request = try request(for: repositoryPath, of: repository, revision: revision, offset: offset)
            try await transfer(request, into: partial, offset: offset)
        }
        guard Self.length(of: partial) == expectedBytes else {
            try? FileManager.default.removeItem(at: partial)
            throw ModelManagementError.downloadFailed(detail: "\(repositoryPath) arrived with an unexpected length")
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: partial, to: destination)
        } catch {
            throw ModelErrorTranslator.translate(error)
        }
    }

    private func request(
        for path: String,
        of repository: String,
        revision: String,
        offset: Int64
    ) throws -> URLRequest {
        guard var url = URL(string: endpoint) else {
            throw ModelManagementError.downloadFailed(detail: "Invalid repository address: \(endpoint)")
        }
        url.append(path: "\(repository)/resolve/\(revision)/\(path)", directoryHint: .notDirectory)
        var request = URLRequest(url: url)
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        return request
    }

    private func transfer(_ request: URLRequest, into partial: URL, offset: Int64) async throws {
        if !FileManager.default.fileExists(atPath: partial.path(percentEncoded: false)) {
            guard FileManager.default.createFile(atPath: partial.path(percentEncoded: false), contents: nil) else {
                throw ModelManagementError.storageAccessDenied(detail: "Could not create \(partial.lastPathComponent)")
            }
        }
        let transfer = FileTransfer(partial: partial, offset: offset)
        let task = session.dataTask(with: request)
        task.delegate = transfer
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    transfer.start(task, continuation: continuation)
                }
            } onCancel: {
                task.cancel()
            }
        } catch {
            throw ModelErrorTranslator.translate(error)
        }
        try Task.checkCancellation()
    }

    private static func length(of file: URL) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))
        return (attributes?[.size] as? NSNumber)?.int64Value
    }
}

/// Writes one response into a partial file as it arrives. Callbacks come one at a time on the session's queue; the
/// state is behind a lock because cancellation and the start come from elsewhere.
private final class FileTransfer: NSObject, URLSessionDataDelegate, Sendable {
    private struct State {
        var handle: FileHandle?
        var continuation: CheckedContinuation<Void, any Error>?
        var failure: (any Error)?
    }

    private let partial: URL
    private let offset: Int64
    private let state = Mutex(State())

    init(partial: URL, offset: Int64) {
        self.partial = partial
        self.offset = offset
    }

    func start(_ task: URLSessionDataTask, continuation: CheckedContinuation<Void, any Error>) {
        state.withLock { $0.continuation = continuation }
        task.resume()
    }

    /// A range answer continues the file; a full answer, from a server that ignored the range, starts it over.
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        do {
            let handle = try FileHandle(forWritingTo: partial)
            switch status {
            case 206 where offset > 0:
                try handle.seekToEnd()
            case 200:
                try handle.truncate(atOffset: 0)
            case 404:
                throw ModelManagementError.modelUnavailable
            default:
                throw ModelManagementError.downloadFailed(detail: "The repository answered with HTTP \(status)")
            }
            state.withLock { $0.handle = handle }
            completionHandler(.allow)
        } catch {
            state.withLock { $0.failure = error }
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let failure: (any Error)? = state.withLock { state in
            do {
                try state.handle?.write(contentsOf: data)
                return nil
            } catch {
                state.failure = error
                return error
            }
        }
        if failure != nil {
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (continuation, failure) = state.withLock { state in
            try? state.handle?.close()
            state.handle = nil
            defer { state.continuation = nil }
            return (state.continuation, state.failure ?? error)
        }
        if let failure {
            continuation?.resume(throwing: failure)
        } else {
            continuation?.resume()
        }
    }
}
