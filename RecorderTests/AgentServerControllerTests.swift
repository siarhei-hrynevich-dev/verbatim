import Foundation
import Testing

@testable import Recorder

@MainActor
struct AgentServerControllerTests {
    let host = FakeAgentServerHost()
    let repository = InMemoryAgentServerSettingsRepository()

    private func makeController() -> AgentServerController {
        AgentServerController(host: host, repository: repository)
    }

    @Test func aFirstLaunchMakesATokenAndStaysOff() async {
        let controller = makeController()
        controller.start()
        await controller.waitUntilSettled()

        #expect(AgentServerSettings.isValidToken(controller.settings.token))
        #expect(repository.settings == controller.settings)
        #expect(controller.state == .stopped)
        #expect(host.starts.isEmpty)
    }

    @Test func turningItOnListensAndOffStops() async {
        let controller = makeController()

        controller.setEnabled(true)
        await controller.waitUntilSettled()
        #expect(controller.state == .running(port: AgentServerSettings.defaultPort))
        #expect(host.starts == [.init(port: AgentServerSettings.defaultPort, token: controller.settings.token)])

        controller.setEnabled(false)
        await controller.waitUntilSettled()
        #expect(controller.state == .stopped)
        #expect(!host.isRunning)
        #expect(repository.settings?.isEnabled == false)
    }

    @Test func quickChangesEndInTheLastState() async {
        let controller = makeController()

        controller.setEnabled(true)
        controller.setEnabled(false)
        controller.setEnabled(true)
        await controller.waitUntilSettled()

        #expect(controller.state == .running(port: AgentServerSettings.defaultPort))
        #expect(host.isRunning)
    }

    @Test func aNewPortOrTokenRestartsTheServer() async throws {
        let controller = makeController()
        controller.setEnabled(true)
        let firstToken = controller.settings.token

        try controller.setPort(50_000)
        controller.regenerateToken()
        await controller.waitUntilSettled()

        #expect(controller.state == .running(port: 50_000))
        #expect(host.starts.last?.port == 50_000)
        #expect(host.starts.last?.token != firstToken)
        #expect(repository.settings?.port == 50_000)
    }

    @Test func anInvalidPortChangesNothing() {
        let controller = makeController()

        #expect(throws: AgentServerSettingsError.invalidPort) {
            try controller.setPort(80)
        }
        #expect(controller.settings.port == AgentServerSettings.defaultPort)
    }

    @Test func aFailureIsShownAndCanBeRetried() async {
        host.failNextStart(with: .portInUse(AgentServerSettings.defaultPort))
        let controller = makeController()

        controller.setEnabled(true)
        await controller.waitUntilSettled()
        #expect(controller.state == .failed(.portInUse(AgentServerSettings.defaultPort)))

        controller.retry()
        await controller.waitUntilSettled()
        #expect(controller.state == .running(port: AgentServerSettings.defaultPort))
    }

    @Test func storedSettingsAreUsedAtLaunch() async {
        let stored = AgentServerSettings(isEnabled: true, port: 51_000, token: AgentServerSettings.makeToken())
        repository.saveSettings(stored)
        let controller = makeController()

        controller.start()
        await controller.waitUntilSettled()

        #expect(controller.settings == stored)
        #expect(host.starts == [.init(port: 51_000, token: stored.token)])
    }

    @Test func settingsSurviveInUserDefaults() throws {
        let suite = "AgentServerTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = UserDefaultsAgentServerRepository(defaults: defaults)
        let settings = AgentServerSettings(isEnabled: true, port: 52_000, token: AgentServerSettings.makeToken())

        #expect(repository.loadSettings() == nil)
        repository.saveSettings(settings)
        #expect(repository.loadSettings() == settings)
    }

    @Test func theSettingsTabOffersWhatAgentsNeed() async {
        let controller = makeController()
        let viewModel = AgentSettingsViewModel(controller: controller)

        viewModel.isEnabled = true
        await controller.waitUntilSettled()
        viewModel.portText = "99"
        viewModel.applyPort()

        #expect(viewModel.isRunning)
        #expect(viewModel.portIssue != nil)
        #expect(viewModel.claudeCodeCommand.contains("--transport http verbatim http://127.0.0.1:47823/mcp"))
        #expect(viewModel.claudeCodeCommand.contains("Bearer \(controller.settings.token)"))
        #expect(viewModel.jsonConfiguration.contains("\"url\": \"http://127.0.0.1:47823/mcp\""))
        #expect(!viewModel.tokenDisplay.contains(controller.settings.token))
    }
}

/// The real server on a free loopback port, answered through the real endpoint.
@MainActor
struct MCPHTTPServerTests {
    @Test func anAgentCanInitializeOverHTTP() async throws {
        let environment = try KnowledgeTestEnvironment()
        let server = MCPHTTPServer(
            endpoint: MCPEndpoint(toolbox: MCPToolbox(knowledge: environment.knowledge), serverVersion: "1.0")
        )
        let token = AgentServerSettings.makeToken()
        let port = try await server.start(port: 0, token: token)
        defer { Task { await server.stop() } }

        let url = try #require(URL(string: "http://127.0.0.1:\(port)/mcp"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try (["jsonrpc": "2.0", "id": 7, "method": "initialize", "params": [:]] as JSONValue)
            .encoded()
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let reply = try JSONValue.decoded(from: data)
        #expect(reply["id"] == 7)
        #expect(reply["result"]?["serverInfo"]?["name"] == "verbatim")

        request.setValue("Bearer wrong", forHTTPHeaderField: "Authorization")
        let (_, refused) = try await URLSession(configuration: .ephemeral).data(for: request)
        #expect((refused as? HTTPURLResponse)?.statusCode == 401)
    }

    @Test func aPortInUseIsReported() async throws {
        let first = LocalHTTPServer()
        let second = LocalHTTPServer()
        let port = try await first.start(port: 0) { _ in HTTPResponse(status: 200) }

        await #expect(throws: AgentServerFailure.portInUse(port)) {
            try await second.start(port: port) { _ in HTTPResponse(status: 200) }
        }
        await first.stop()
        await second.stop()
    }
}
