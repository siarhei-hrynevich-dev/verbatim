import Foundation
import Observation

/// Presentation state of Settings › Agents: turning the MCP server on, its port and token, and what to paste into an
/// agent to connect it. The server and its settings belong to `AgentServerController`.
@MainActor
@Observable
final class AgentSettingsViewModel {
    /// The port as typed, applied on Return or when the field loses focus.
    var portText: String
    var isTokenRevealed = false
    private(set) var portIssue: String?

    @ObservationIgnored private let controller: AgentServerController

    init(controller: AgentServerController) {
        self.controller = controller
        portText = String(controller.settings.port)
    }

    var isEnabled: Bool {
        get { controller.settings.isEnabled }
        set { controller.setEnabled(newValue) }
    }

    var isRunning: Bool {
        controller.state.isRunning
    }

    var canRetry: Bool {
        if case .failed = controller.state {
            return true
        }
        return false
    }

    var statusTitle: String {
        switch controller.state {
        case .stopped: String(localized: "Off")
        case .starting: String(localized: "Starting…")
        case .running: String(localized: "Running")
        case .failed: String(localized: "Not Running")
        }
    }

    var statusDetail: String {
        switch controller.state {
        case .stopped:
            String(localized: "Agents can’t reach your recordings.")
        case .starting:
            String(localized: "Opening port \(String(controller.settings.port)) on this Mac.")
        case .running(let port):
            String(localized: "Agents on this Mac can connect at port \(String(port)).")
        case .failed(.portInUse(let port)):
            String(localized: "Port \(String(port)) is used by another app. Choose another port, then try again.")
        case .failed(.notPermitted):
            String(localized: "macOS didn’t allow Verbatim to open a port.")
        case .failed(.failed(let detail)):
            String(localized: "The server couldn’t start. \(detail)")
        }
    }

    var serverURL: String {
        controller.settings.endpointURL.absoluteString
    }

    var token: String {
        controller.settings.token
    }

    var tokenDisplay: String {
        isTokenRevealed ? token : String(repeating: "•", count: 24)
    }

    /// Adds the server to Claude Code.
    var claudeCodeCommand: String {
        "claude mcp add --transport http verbatim \(serverURL) --header \"Authorization: Bearer \(token)\""
    }

    /// The `mcpServers` entry most agents and editors read from their configuration file.
    var jsonConfiguration: String {
        """
        {
          "mcpServers": {
            "verbatim": {
              "type": "http",
              "url": "\(serverURL)",
              "headers": {
                "Authorization": "Bearer \(token)"
              }
            }
          }
        }
        """
    }

    func applyPort() {
        guard let port = Int(portText.trimmingCharacters(in: .whitespaces)) else {
            portIssue = String(localized: "Enter a number from 1024 to 65535.")
            return
        }
        do {
            try controller.setPort(port)
            portIssue = nil
            portText = String(controller.settings.port)
        } catch {
            portIssue = String(localized: "Enter a number from 1024 to 65535.")
        }
    }

    func regenerateToken() {
        controller.regenerateToken()
    }

    func retry() {
        controller.retry()
    }
}
