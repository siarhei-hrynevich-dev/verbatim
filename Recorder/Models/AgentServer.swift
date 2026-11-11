import Foundation

/// How the MCP server that lets AI agents on this Mac read recordings is set up. It listens on the loopback interface
/// only, and every request must carry the token.
struct AgentServerSettings: Equatable, Sendable {
    var isEnabled = false
    var port = Self.defaultPort
    var token: String

    /// Unassigned by IANA and rarely used by developer tools.
    static let defaultPort = 47_823
    /// Ports below 1024 are privileged.
    static let allowedPorts = 1_024...65_535
    /// 32 random bytes, as base64url without padding.
    private static let tokenByteCount = 32

    init(isEnabled: Bool = false, port: Int = Self.defaultPort, token: String) {
        self.isEnabled = isEnabled
        self.port = port
        self.token = token
    }

    /// Throws `AgentServerSettingsError.invalidPort` outside `allowedPorts`.
    static func validatedPort(_ port: Int) throws(AgentServerSettingsError) -> Int {
        guard allowedPorts.contains(port) else {
            throw .invalidPort
        }
        return port
    }

    /// A token is stored as generated; anything shorter than one was not made here and is replaced.
    static func isValidToken(_ token: String) -> Bool {
        token.count >= 32 && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// A new secret. `SystemRandomNumberGenerator` is cryptographically secure on Apple platforms.
    static func makeToken<Generator: RandomNumberGenerator>(using generator: inout Generator) -> String {
        let bytes = (0..<tokenByteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return makeToken(using: &generator)
    }

    /// Where agents connect.
    var endpointURL: URL {
        // Built from a validated integer port, which always forms a URL.
        URL(string: "http://127.0.0.1:\(port)/mcp") ?? URL(filePath: "/")
    }
}

enum AgentServerSettingsError: Error, Equatable, Sendable {
    case invalidPort
}

/// Why the server could not listen. User-facing wording belongs to Presentation.
enum AgentServerFailure: Error, Equatable, Sendable {
    /// Another process, or another copy of the app, listens on the port.
    case portInUse(Int)
    /// The system refused to let the app listen, as when the sandbox lacks the entitlement.
    case notPermitted
    case failed(detail: String)
}

/// Whether the server is listening.
enum AgentServerState: Equatable, Sendable {
    case stopped
    case starting
    case running(port: Int)
    case failed(AgentServerFailure)

    var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }
}
