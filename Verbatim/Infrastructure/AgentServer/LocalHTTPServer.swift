import Foundation
import Network
import os

/// A minimal HTTP/1.1 server on the loopback interface, for the MCP endpoint. One request at a time per connection,
/// with persistent connections; bodies must state their length.
///
/// Built on Network.framework rather than a server package: the MCP endpoint needs a handful of POST requests, and a
/// framework would add a dependency for nothing else. Only `127.0.0.1` is bound, so nothing outside this Mac can
/// connect.
actor LocalHTTPServer {
    typealias Responder = @Sendable (HTTPRequest) async -> HTTPResponse

    /// Agents keep one or two connections each; this bounds what a misbehaving local process can hold open.
    static let maximumConnections = 32

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let queue = DispatchQueue(label: "\(AppIdentity.bundleIdentifier).AgentServer")

    /// Starts listening and returns the bound port: the one asked for, or a free one for 0. Throws
    /// `AgentServerFailure`. Whatever ran before is stopped first.
    func start(port: Int, responder: @escaping Responder) async throws -> Int {
        stop()
        guard let requestedPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            throw AgentServerFailure.failed(detail: "Invalid port \(port)")
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: requestedPort)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw Self.failure(from: error, port: port)
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.accept(connection, responder: responder)
            }
        }
        self.listener = listener
        let boundPort = try await Self.waitUntilReady(listener, on: queue, port: port)
        guard self.listener === listener else {
            // Stopped while starting.
            listener.cancel()
            throw CancellationError()
        }
        return boundPort
    }

    var isListening: Bool {
        listener != nil
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
    }

    // MARK: - Listening

    private static func waitUntilReady(_ listener: NWListener, on queue: DispatchQueue, port: Int) async throws -> Int {
        let once = ResumeOnce()
        return try await withCheckedThrowingContinuation { continuation in
            let finish: @Sendable (Result<Int, any Error>) -> Void = { result in
                if once.claim() {
                    continuation.resume(with: result)
                }
            }
            // Weak: the listener keeps this handler for its whole life.
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    finish(.success(Int(listener?.port?.rawValue ?? UInt16(clamping: port))))
                case .failed(let error), .waiting(let error):
                    // Waiting means the port cannot be had now; the user is told rather than kept waiting.
                    listener?.cancel()
                    finish(.failure(failure(from: error, port: port)))
                case .cancelled:
                    finish(.failure(CancellationError()))
                case .setup:
                    break
                @unknown default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private static func failure(from error: any Error, port: Int) -> AgentServerFailure {
        if case NWError.posix(let code) = error {
            switch code {
            case .EADDRINUSE: return .portInUse(port)
            case .EACCES, .EPERM: return .notPermitted
            default: break
            }
        }
        return .failed(detail: String(describing: error))
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection, responder: @escaping Responder) {
        guard listener != nil, connections.count < Self.maximumConnections else {
            connection.cancel()
            return
        }
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.start(queue: queue)
        Task {
            await Self.serve(connection, responder: responder)
            connection.cancel()
            self.forget(key)
        }
    }

    private func forget(_ key: ObjectIdentifier) {
        connections[key] = nil
    }

    /// Answers requests until the client closes the connection, asks to, or sends something unreadable.
    private static func serve(_ connection: NWConnection, responder: Responder) async {
        var buffer = Data()
        var hasSentContinue = false
        do {
            while true {
                switch HTTPRequestParser.parse(buffer) {
                case .incomplete(let expectsContinue):
                    if expectsContinue, !hasSentContinue {
                        try await send(HTTPResponse.continueInterim, on: connection)
                        hasSentContinue = true
                    }
                    guard let received = try await receive(on: connection) else {
                        return
                    }
                    buffer.append(received)
                case .invalid(let status):
                    let response = HTTPResponse.text("Unsupported request", status: status)
                    try await send(response.serialized(keepingAlive: false), on: connection)
                    return
                case let .complete(request, consumedBytes):
                    buffer = Data(buffer.dropFirst(consumedBytes))
                    hasSentContinue = false
                    let response = await responder(request)
                    let keepsAlive = !request.closesConnection
                    try await send(response.serialized(keepingAlive: keepsAlive), on: connection)
                    guard keepsAlive else {
                        return
                    }
                }
            }
        } catch {
            // A client going away mid-request is ordinary; anything else is worth a note.
            logger.debug("Connection ended: \(String(describing: error), privacy: .public)")
        }
    }

    /// The next bytes, or `nil` once the client has closed its side.
    private static func receive(on connection: NWConnection) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    private static func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    private static let logger = Logger(category: "AgentServer")
}

/// Lets only the first of several callbacks resume a continuation: a listener reports `ready`, then `cancelled`
/// when stopped.
private final class ResumeOnce: Sendable {
    private let hasResumed = OSAllocatedUnfairLock(initialState: false)

    /// True the first time only.
    func claim() -> Bool {
        hasResumed.withLock { hasResumed in
            defer { hasResumed = true }
            return !hasResumed
        }
    }
}
