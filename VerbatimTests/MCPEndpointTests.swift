import Foundation
import Testing

@testable import Verbatim

/// The MCP endpoint: who may call it, the protocol, and the tools over a real database.
@MainActor
struct MCPEndpointTests {
    let environment: KnowledgeTestEnvironment
    let endpoint: MCPEndpoint

    static let token = "test-token-0123456789abcdefghijklmnopqrstuvwx"
    static let port = 47_823

    init() throws {
        environment = try KnowledgeTestEnvironment()
        var toolbox = MCPToolbox(knowledge: environment.knowledge)
        toolbox.now = { Date(timeIntervalSince1970: 1_800_000_000) }
        toolbox.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        endpoint = MCPEndpoint(toolbox: toolbox, serverVersion: "1.0")
    }

    private func request(
        _ body: JSONValue,
        headers: [String: String] = [:],
        method: String = "POST",
        path: String = "/mcp"
    ) throws -> HTTPRequest {
        var all = ["host": "127.0.0.1:\(Self.port)", "authorization": "Bearer \(Self.token)"]
        for (name, value) in headers {
            all[name.lowercased()] = value
        }
        return HTTPRequest(
            method: method,
            path: path,
            headers: all.filter { !$0.value.isEmpty },
            body: try body.encoded()
        )
    }

    private func send(_ request: HTTPRequest) async -> HTTPResponse {
        await endpoint.respond(to: request, token: Self.token, port: Self.port)
    }

    private func call(_ method: String, _ params: JSONValue = [:]) async throws -> JSONValue {
        let response = await send(
            try request(["jsonrpc": "2.0", "id": 1, "method": .string(method), "params": params])
        )
        #expect(response.status == 200)
        return try JSONValue.decoded(from: response.body)
    }

    private func tool(_ name: String, _ arguments: JSONValue) async throws -> JSONValue {
        let reply = try await call("tools/call", ["name": .string(name), "arguments": arguments])
        return try #require(reply["result"])
    }

    // MARK: - Access

    @Test func requestsWithoutTheTokenAreRefused() async throws {
        let missing = await send(
            try request(["jsonrpc": "2.0", "id": 1, "method": "ping"], headers: ["authorization": ""])
        )
        let wrong = await send(
            try request(["jsonrpc": "2.0", "id": 1, "method": "ping"], headers: ["authorization": "Bearer nope"])
        )

        #expect(missing.status == 401)
        #expect(missing.header("WWW-Authenticate")?.hasPrefix("Bearer") == true)
        #expect(wrong.status == 401)
    }

    @Test func requestsFromWebPagesOrOtherHostsAreRefused() async throws {
        let ping: JSONValue = ["jsonrpc": "2.0", "id": 1, "method": "ping"]

        let page = await send(try request(ping, headers: ["origin": "https://example.com"]))
        let rebound = await send(try request(ping, headers: ["host": "evil.example:47823"]))
        let local = await send(try request(ping, headers: ["origin": "http://localhost:\(Self.port)"]))

        #expect(page.status == 403)
        #expect(rebound.status == 403)
        #expect(local.status == 200)
    }

    @Test func onlyPostToTheEndpointIsServed() async throws {
        let stream = await send(try request(.null, method: "GET"))
        let elsewhere = await send(try request(.null, path: "/.well-known/oauth-protected-resource"))

        #expect(stream.status == 405)
        #expect(stream.header("Allow") == "POST")
        #expect(elsewhere.status == 404)
    }

    // MARK: - Protocol

    @Test func initializeAgreesOnAVersionAndOffersTools() async throws {
        let known = try await call("initialize", ["protocolVersion": "2025-06-18", "capabilities": [:]])
        let unknown = try await call("initialize", ["protocolVersion": "1999-01-01"])

        #expect(known["result"]?["protocolVersion"] == "2025-06-18")
        #expect(unknown["result"]?["protocolVersion"] == .string(MCPEndpoint.protocolVersions[0]))
        #expect(known["result"]?["capabilities"]?["tools"] != nil)
        #expect(known["result"]?["serverInfo"]?["name"] == "verbatim")
        #expect(known["result"]?["instructions"]?.stringValue?.contains("search_recordings") == true)
    }

    @Test func notificationsAreAcceptedWithoutAReply() async throws {
        let response = await send(try request(["jsonrpc": "2.0", "method": "notifications/initialized"]))

        #expect(response.status == 202)
        #expect(response.body.isEmpty)
    }

    @Test func unknownMethodsAndBadJSONAreJSONRPCErrors() async throws {
        let unknown = try await call("resources/list")
        let garbled = await send(
            HTTPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["host": "localhost:\(Self.port)", "authorization": "Bearer \(Self.token)"],
                body: Data("{".utf8)
            )
        )

        #expect(unknown["error"]?["code"] == .number(-32_601))
        #expect(garbled.status == 400)
        #expect(try JSONValue.decoded(from: garbled.body)["error"]?["code"] == .number(-32_700))
    }

    @Test func everyToolIsListedWithASchema() async throws {
        let reply = try await call("tools/list")

        guard case .array(let tools) = reply["result"]?["tools"] else {
            Issue.record("Expected a list of tools")
            return
        }
        let names = Set(tools.compactMap { $0["name"]?.stringValue })
        #expect(names == MCPToolbox.toolNames)
        #expect(tools.allSatisfy { $0["inputSchema"]?["type"] == "object" })
        #expect(tools.allSatisfy { $0["annotations"]?["readOnlyHint"] == true })
    }

    // MARK: - Tools

    @Test func searchFindsTheMomentAndLinksToIt() async throws {
        let recording = try await environment.addRecording(title: "Планёрка", lines: SearchFixtures.planning)
        await environment.index([recording.id])

        let result = try await tool(MCPToolName.search, ["query": "звук микрофона", "limit": 3])

        let hit = try #require(
            result["structuredContent"]?["hits"].flatMap { hits -> JSONValue? in
                guard case .array(let items) = hits else { return nil }
                return items.first
            }
        )
        #expect(result["isError"] == false)
        #expect(result["structuredContent"]?["semantic_search"] == "used")
        #expect(hit["recording_id"] == .string(recording.id.uuidString))
        #expect(hit["recording_title"] == "Планёрка")
        #expect(hit["source"] == "transcript")
        #expect(hit["link"]?.stringValue?.hasPrefix("verbatim://recording/\(recording.id.uuidString)?t=") == true)
        #expect(hit["recorded_at"]?.stringValue?.hasSuffix("+01:00") == true)
        #expect(hit["chunk_id"] != nil)
    }

    @Test func aTranscriptIsReadAroundASearchResult() async throws {
        let recording = try await environment.addRecording(title: "Planning", lines: SearchFixtures.planning)
        await environment.index([recording.id])
        let search = try await tool(MCPToolName.search, ["query": "мониторах", "sources": ["transcript"]])
        let chunkID = try #require(
            search["structuredContent"]?["hits"].flatMap { hits -> JSONValue? in
                guard case .array(let items) = hits else { return nil }
                return items.first?["chunk_id"]
            }
        )

        let result = try await tool(
            MCPToolName.transcript,
            ["recording_id": .string(recording.id.uuidString), "around_chunk_id": chunkID, "context_seconds": 0]
        )

        guard case .array(let segments) = result["structuredContent"]?["segments"] else {
            Issue.record("Expected segments")
            return
        }
        #expect(segments.contains { $0["text"] == .string(SearchFixtures.planning[2]) })
        #expect(segments.first?["speaker"] == "microphone")
        #expect(result["structuredContent"]?["truncated"] == false)
    }

    @Test func listingReturnsRecordingsWithTheCurrentDate() async throws {
        _ = try await environment.addRecording(title: "Standup", lines: nil)

        let result = try await tool(MCPToolName.list, ["from": "2027-01", "type": "video"])

        #expect(result["structuredContent"]?["total_count"] == 1)
        #expect(result["structuredContent"]?["now"]?.stringValue?.hasPrefix("2027-01-15T") == true)
        guard case .array(let recordings) = result["structuredContent"]?["recordings"] else {
            Issue.record("Expected recordings")
            return
        }
        #expect(recordings.first?["processing"]?["transcript"] == "none")
        #expect(recordings.first?["type"] == "video")
    }

    @Test func mistakesComeBackAsToolErrorsTheAgentCanFix() async throws {
        let badID = try await tool(MCPToolName.summary, ["recording_id": "nope"])
        let missing = try await tool(MCPToolName.summary, ["recording_id": .string(UUID().uuidString)])
        let noQuery = try await tool(MCPToolName.search, [:])
        let badDate = try await tool(MCPToolName.list, ["from": "last tuesday"])
        let badTag = try await tool(MCPToolName.search, ["query": "x", "tags": ["nonexistent"]])

        for result in [badID, missing, noQuery, badDate, badTag] {
            #expect(result["isError"] == true)
        }
        #expect(Self.text(of: noQuery).contains("missing `query`"))
        #expect(Self.text(of: badDate).contains("is not a date"))
        #expect(Self.text(of: badTag).contains("work, personal"))
    }

    @Test func unknownToolsAreProtocolErrors() async throws {
        let reply = try await call("tools/call", ["name": "delete_recording", "arguments": [:]])

        #expect(reply["error"]?["code"] == .number(-32_602))
    }

    private static func text(of result: JSONValue) -> String {
        guard case .array(let content) = result["content"] else {
            return ""
        }
        return content.first?["text"]?.stringValue ?? ""
    }
}
