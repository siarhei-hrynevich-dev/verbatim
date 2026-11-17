import Foundation
import Observation
import os

/// The single owner of the MCP server's settings and lifecycle: whether it should run, on which port, with which
/// token, and whether it does. Created by App and outlives every window.
///
/// Changes take effect one after another in the order they were made, so a quick toggle can never leave the server in
/// a state other than the one last asked for. Starting is never automatic in tests; App calls `start()` at launch.
@MainActor
@Observable
final class AgentServerController {
    private(set) var settings: AgentServerSettings
    private(set) var state = AgentServerState.stopped

    @ObservationIgnored private let host: any AgentServerHosting
    @ObservationIgnored private let repository: any AgentServerSettingsRepository
    /// The latest change being applied; each one waits for the one before.
    @ObservationIgnored private var transition: Task<Void, Never>?

    init(host: any AgentServerHosting, repository: any AgentServerSettingsRepository) {
        self.host = host
        self.repository = repository
        if let stored = repository.loadSettings() {
            settings = stored
        } else {
            settings = AgentServerSettings(token: AgentServerSettings.makeToken())
            repository.saveSettings(settings)
        }
    }

    /// Starts the server when the user turned it on. Called once at launch.
    func start() {
        apply()
    }

    func setEnabled(_ isEnabled: Bool) {
        guard settings.isEnabled != isEnabled else {
            return
        }
        update { $0.isEnabled = isEnabled }
    }

    /// Throws `AgentServerSettingsError.invalidPort` and changes nothing for a port outside the allowed range.
    func setPort(_ port: Int) throws(AgentServerSettingsError) {
        let valid = try AgentServerSettings.validatedPort(port)
        guard settings.port != valid else {
            return
        }
        update { $0.port = valid }
    }

    /// Replaces the token. Connected agents are refused until they are given the new one.
    func regenerateToken() {
        update { $0.token = AgentServerSettings.makeToken() }
    }

    /// Tries again after a failure, as after freeing the port.
    func retry() {
        apply()
    }

    /// Waits until every change made so far has taken effect. For tests and quitting.
    func waitUntilSettled() async {
        while let current = transition {
            await current.value
            if transition == current {
                return
            }
        }
    }

    private func update(_ change: (inout AgentServerSettings) -> Void) {
        change(&settings)
        repository.saveSettings(settings)
        apply()
    }

    private func apply() {
        let previous = transition
        let desired = settings
        transition = Task { [weak self] in
            await previous?.value
            await self?.reconcile(to: desired)
        }
    }

    /// The host keeps listening when only the token changed, and moves when the port did.
    private func reconcile(to desired: AgentServerSettings) async {
        guard desired.isEnabled else {
            await host.stop()
            state = .stopped
            return
        }
        // Taking a new token keeps it running throughout.
        if !state.isRunning {
            state = .starting
        }
        do {
            let port = try await host.start(port: desired.port, token: desired.token)
            state = .running(port: port)
            Self.logger.info("Agent server listening on port \(port, privacy: .public)")
        } catch let failure as AgentServerFailure {
            state = .failed(failure)
            Self.logger.error("Agent server could not start: \(String(describing: failure), privacy: .public)")
        } catch {
            state = .failed(.failed(detail: String(describing: error)))
            Self.logger.error("Agent server could not start: \(String(describing: error), privacy: .public)")
        }
    }

    private static let logger = Logger(category: "AgentServer")
}
