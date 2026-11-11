import Foundation
import Testing

@testable import Recorder

struct RecordingLinkTests {
    private let id = UUID(uuidString: "6F1D2A40-0000-4000-8000-0000000000AB") ?? UUID()

    @Test func aLinkNamesTheRecordingAndWholeSeconds() {
        let link = RecordingLink(recordingID: id, time: 754.9)

        #expect(link.url.absoluteString == "verbatim://recording/\(id.uuidString)?t=754")
        #expect(RecordingLink(url: link.url) == RecordingLink(recordingID: id, time: 754))
    }

    @Test func aLinkWithoutTimeOpensFromTheStart() throws {
        let url = try #require(URL(string: "verbatim://recording/\(id.uuidString.lowercased())"))

        #expect(RecordingLink(url: url) == RecordingLink(recordingID: id))
        #expect(RecordingLink(recordingID: id).url.query == nil)
    }

    @Test(arguments: [
        "https://recording/6F1D2A40-0000-4000-8000-0000000000AB",
        "verbatim://library/6F1D2A40-0000-4000-8000-0000000000AB",
        "verbatim://recording/not-an-id",
        "verbatim://recording/"
    ])
    func otherURLsAreNotLinks(_ text: String) throws {
        let url = try #require(URL(string: text))
        #expect(RecordingLink(url: url) == nil)
    }

    @Test func aTimeThatIsNotOnTheTimelineIsDropped() throws {
        let url = try #require(URL(string: "verbatim://recording/\(id.uuidString)?t=-5"))

        #expect(RecordingLink(url: url)?.time == nil)
        #expect(RecordingLink(recordingID: id, time: .nan).time == nil)
    }
}

struct AgentServerSettingsTests {
    @Test func tokensAreLongRandomAndURLSafe() {
        let first = AgentServerSettings.makeToken()
        let second = AgentServerSettings.makeToken()

        #expect(first.count == 43)
        #expect(first != second)
        #expect(AgentServerSettings.isValidToken(first))
        #expect(!first.contains("+") && !first.contains("/") && !first.contains("="))
    }

    @Test func shortOrForeignTokensAreNotValid() {
        #expect(!AgentServerSettings.isValidToken("secret"))
        #expect(!AgentServerSettings.isValidToken(String(repeating: "ä", count: 40)))
    }

    @Test(arguments: [0, 80, 1_023, 65_536])
    func portsOutsideTheRangeAreRefused(_ port: Int) {
        #expect(throws: AgentServerSettingsError.invalidPort) {
            try AgentServerSettings.validatedPort(port)
        }
    }

    @Test func theEndpointIsOnTheLoopbackAddress() throws {
        let settings = AgentServerSettings(port: 50_123, token: "t")

        #expect(try AgentServerSettings.validatedPort(1_024) == 1_024)
        #expect(settings.endpointURL.absoluteString == "http://127.0.0.1:50123/mcp")
    }
}

struct HTTPRequestParserTests {
    private func bytes(_ text: String) -> Data {
        Data(text.utf8)
    }

    @Test func aRequestWithABodyIsReadWhole() throws {
        let buffer = bytes("POST /mcp?x=1 HTTP/1.1\r\nHost: 127.0.0.1:9\r\nContent-Length: 4\r\n\r\nbody")

        guard case let .complete(request, consumed) = HTTPRequestParser.parse(buffer) else {
            Issue.record("Expected a complete request")
            return
        }
        #expect(request.method == "POST")
        #expect(request.path == "/mcp")
        #expect(request.header("HOST") == "127.0.0.1:9")
        #expect(request.body == bytes("body"))
        #expect(consumed == buffer.count)
    }

    @Test func partialHeadersAndBodiesWaitForMore() {
        #expect(HTTPRequestParser.parse(bytes("POST /mcp HTTP/1.1\r\nHost: a")) == .incomplete(expectsContinue: false))
        let partialBody = bytes("POST /mcp HTTP/1.1\r\nContent-Length: 10\r\nExpect: 100-continue\r\n\r\nabc")
        #expect(HTTPRequestParser.parse(partialBody) == .incomplete(expectsContinue: true))
    }

    @Test func aSecondRequestStaysInTheBuffer() {
        let first = "GET /mcp HTTP/1.1\r\nConnection: close\r\n\r\n"
        let buffer = bytes(first + "POST /mcp HTTP/1.1\r\n")

        guard case let .complete(request, consumed) = HTTPRequestParser.parse(buffer) else {
            Issue.record("Expected a complete request")
            return
        }
        #expect(consumed == first.utf8.count)
        #expect(request.closesConnection)
    }

    @Test func unsupportedOrMalformedRequestsAreRefused() {
        let chunked = bytes("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n")
        let huge = bytes("POST /mcp HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n")
        let garbled = bytes("hello\r\n\r\n")
        let endlessHeaders = Data(repeating: 65, count: HTTPRequestParser.maximumHeaderBytes + 1)

        #expect(HTTPRequestParser.parse(chunked) == .invalid(status: 501))
        #expect(HTTPRequestParser.parse(huge) == .invalid(status: 413))
        #expect(HTTPRequestParser.parse(garbled) == .invalid(status: 400))
        #expect(HTTPRequestParser.parse(endlessHeaders) == .invalid(status: 431))
    }

    @Test func responsesStateTheirLength() {
        let response = HTTPResponse.json(bytes("{}"))

        let text = String(bytes: response.serialized(keepingAlive: true), encoding: .utf8) ?? ""

        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Content-Length: 2\r\n"))
        #expect(text.contains("Connection: keep-alive\r\n"))
        #expect(text.hasSuffix("\r\n\r\n{}"))
    }
}
