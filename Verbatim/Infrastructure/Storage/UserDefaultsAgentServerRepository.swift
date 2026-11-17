import Foundation

/// Stores the MCP server's settings as individual defaults. The token lives here too: it guards the same recordings
/// that the app's own container holds, and only this app and the user can read either.
struct UserDefaultsAgentServerRepository: AgentServerSettingsRepository {
    private enum Key {
        static let isEnabled = "agentServer.isEnabled"
        static let port = "agentServer.port"
        static let token = "agentServer.token"
    }

    /// UserDefaults is documented as thread-safe, but is not marked Sendable.
    nonisolated(unsafe) let defaults: UserDefaults

    func loadSettings() -> AgentServerSettings? {
        guard let token = defaults.string(forKey: Key.token), AgentServerSettings.isValidToken(token) else {
            return nil
        }
        var settings = AgentServerSettings(token: token)
        settings.isEnabled = defaults.bool(forKey: Key.isEnabled)
        if let port = defaults.object(forKey: Key.port) as? Int, AgentServerSettings.allowedPorts.contains(port) {
            settings.port = port
        }
        return settings
    }

    func saveSettings(_ settings: AgentServerSettings) {
        defaults.set(settings.isEnabled, forKey: Key.isEnabled)
        defaults.set(settings.port, forKey: Key.port)
        defaults.set(settings.token, forKey: Key.token)
    }
}
