import Foundation

/// The Model Context Protocol over Streamable HTTP, at `/mcp`: JSON-RPC messages in POST requests, each answered with
/// one JSON response. The server offers tools only, keeps no sessions and opens no event streams, which the protocol
/// allows; GET and DELETE are refused with 405.
///
/// Every request must come to the loopback address, from no web page other than a local one, with the token as a
/// bearer credential. Any local process can reach the port, and recordings are private.
struct MCPEndpoint: Sendable {
    static let path = "/mcp"
    /// Newest first. The newest one a client asks for is used; otherwise the newest here.
    static let protocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    let toolbox: MCPToolbox
    let serverVersion: String

    func respond(to request: HTTPRequest, token: String, port: Int) async -> HTTPResponse {
        if let refusal = refusal(of: request, token: token, port: port) {
            return refusal
        }
        let message: JSONValue
        do {
            message = try JSONValue.decoded(from: request.body)
        } catch {
            return Self.jsonResponse(Self.error(id: .null, code: -32_700, message: "Parse error"), status: 400)
        }
        switch message {
        case .array(let batch):
            var replies: [JSONValue] = []
            for item in batch {
                if let reply = await reply(to: item) {
                    replies.append(reply)
                }
            }
            return replies.isEmpty ? HTTPResponse(status: 202) : Self.jsonResponse(.array(replies))
        default:
            guard let reply = await reply(to: message) else {
                return HTTPResponse(status: 202)
            }
            return Self.jsonResponse(reply)
        }
    }

    // MARK: - HTTP checks

    private func refusal(of request: HTTPRequest, token: String, port: Int) -> HTTPResponse? {
        guard request.path == Self.path else {
            return .text("Not found", status: 404)
        }
        // A web page can make a browser send requests here under another name (DNS rebinding) or from its own origin.
        guard let host = request.header("host"), Self.isLoopback(authority: host, port: port) else {
            return .text("Forbidden host", status: 403)
        }
        if let origin = request.header("origin"), !Self.isLoopback(origin: origin, port: port) {
            return .text("Forbidden origin", status: 403)
        }
        guard Self.isAuthorized(request.header("authorization"), token: token) else {
            return .text(
                "A bearer token is required. Copy it from Verbatim › Settings › Agents.",
                status: 401,
                headers: [("WWW-Authenticate", "Bearer realm=\"Verbatim\"")]
            )
        }
        guard request.method == "POST" else {
            return .text("Use POST", status: 405, headers: [("Allow", "POST")])
        }
        if let version = request.header("mcp-protocol-version"), !Self.protocolVersions.contains(version) {
            return .text("Unsupported MCP protocol version \(version)", status: 400)
        }
        return nil
    }

    private static func isLoopback(authority: String, port: Int) -> Bool {
        let allowed = ["127.0.0.1:\(port)", "localhost:\(port)"]
        return allowed.contains(authority.lowercased())
    }

    private static func isLoopback(origin: String, port: Int) -> Bool {
        guard let url = URL(string: origin), url.scheme == "http" || url.scheme == "https", let host = url.host() else {
            return false
        }
        return ["127.0.0.1", "localhost"].contains(host.lowercased()) && url.port == port
    }

    /// Compares in time independent of where the values differ, so the token cannot be guessed byte by byte.
    private static func isAuthorized(_ header: String?, token: String) -> Bool {
        guard let header, header.lowercased().hasPrefix("bearer ") else {
            return false
        }
        let given = Array(header.dropFirst("bearer ".count).trimmingCharacters(in: .whitespaces).utf8)
        let expected = Array(token.utf8)
        guard given.count == expected.count, !expected.isEmpty else {
            return false
        }
        return zip(given, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    // MARK: - JSON-RPC

    /// The response to a request, or `nil` for a notification or a response, which get none.
    private func reply(to message: JSONValue) async -> JSONValue? {
        guard let method = message["method"]?.stringValue else {
            return message["id"] == nil
                ? Self.error(id: .null, code: -32_600, message: "Invalid request") : nil
        }
        guard let id = message["id"] else {
            // Notifications such as `notifications/initialized` need no answer.
            return nil
        }
        let params = message["params"] ?? .object([:])
        switch method {
        case "initialize":
            return Self.result(id: id, initializeResult(requested: params["protocolVersion"]?.stringValue))
        case "ping":
            return Self.result(id: id, .object([:]))
        case "tools/list":
            return Self.result(id: id, ["tools": .array(MCPToolbox.definitions)])
        case "tools/call":
            guard let name = params["name"]?.stringValue else {
                return Self.error(id: id, code: -32_602, message: "Missing tool name")
            }
            guard MCPToolbox.toolNames.contains(name) else {
                return Self.error(id: id, code: -32_602, message: "Unknown tool: \(name)")
            }
            return Self.result(id: id, await toolbox.call(name, arguments: params["arguments"] ?? .object([:])))
        default:
            return Self.error(id: id, code: -32_601, message: "Method not found: \(method)")
        }
    }

    private func initializeResult(requested: String?) -> JSONValue {
        let version = requested.flatMap { Self.protocolVersions.contains($0) ? $0 : nil } ?? Self.protocolVersions[0]
        return [
            "protocolVersion": .string(version),
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": [
                "name": "verbatim",
                "title": "Verbatim Recordings",
                "version": .string(serverVersion)
            ],
            "instructions": .string(MCPToolbox.instructions)
        ]
    }

    private static func result(id: JSONValue, _ result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func error(id: JSONValue, code: Int, message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(code)), "message": .string(message)]]
    }

    private static func jsonResponse(_ value: JSONValue, status: Int = 200) -> HTTPResponse {
        do {
            return .json(try value.encoded(), status: status)
        } catch {
            return .text("Could not encode the response", status: 500)
        }
    }
}
