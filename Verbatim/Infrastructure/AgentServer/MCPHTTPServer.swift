import Foundation
import Synchronization

/// The MCP endpoint served over HTTP on the loopback interface: what `AgentServerController` starts and stops.
///
/// A new token on the same port takes effect without closing the port, so the next request is checked against it and
/// no other process can take the port in between.
final class MCPHTTPServer: AgentServerHosting {
    private let http = LocalHTTPServer()
    private let endpoint: MCPEndpoint
    private let serving = Serving()

    init(endpoint: MCPEndpoint) {
        self.endpoint = endpoint
    }

    func start(port: Int, token: String) async throws -> Int {
        if port != 0, serving.current?.port == port, await http.isListening {
            serving.current = Serving.Credentials(port: port, token: token)
            return port
        }
        await stop()
        let endpoint = endpoint
        let serving = serving
        let boundPort = try await http.start(port: port) { request in
            // Requests arriving before listening is confirmed are refused rather than checked against nothing.
            guard let credentials = serving.current else {
                return .text("Starting", status: 503)
            }
            return await endpoint.respond(to: request, token: credentials.token, port: credentials.port)
        }
        serving.current = Serving.Credentials(port: boundPort, token: token)
        return boundPort
    }

    func stop() async {
        serving.current = nil
        await http.stop()
    }
}

/// The port requests must name in their `Host` header and the token they must carry, once listening.
private final class Serving: Sendable {
    struct Credentials {
        let port: Int
        let token: String
    }

    private let credentials = Mutex<Credentials?>(nil)

    var current: Credentials? {
        get { credentials.withLock { $0 } }
        set { credentials.withLock { $0 = newValue } }
    }
}
