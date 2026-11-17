import Foundation

/// One HTTP/1.1 request, as far as the MCP endpoint needs it.
struct HTTPRequest: Equatable, Sendable {
    let method: String
    /// The path without its query.
    let path: String
    /// Names in lowercase; a repeated header keeps its last value.
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    /// HTTP/1.1 keeps connections open unless asked not to.
    var closesConnection: Bool {
        header("connection")?.lowercased().contains("close") ?? false
    }
}

struct HTTPResponse: Equatable, Sendable {
    let status: Int
    var headers: [(String, String)] = []
    var body = Data()

    static func == (lhs: HTTPResponse, rhs: HTTPResponse) -> Bool {
        lhs.status == rhs.status && lhs.body == rhs.body
            && lhs.headers.map { "\($0.0): \($0.1)" } == rhs.headers.map { "\($0.0): \($0.1)" }
    }

    static func json(_ data: Data, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, headers: [("Content-Type", "application/json")], body: data)
    }

    static func text(_ text: String, status: Int, headers: [(String, String)] = []) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: [("Content-Type", "text/plain; charset=utf-8")] + headers,
            body: Data(text.utf8)
        )
    }

    func header(_ name: String) -> String? {
        headers.last { $0.0.caseInsensitiveCompare(name) == .orderedSame }?.1
    }

    /// The bytes to send, with the length and connection headers this server always sets.
    func serialized(keepingAlive: Bool) -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(for: status))\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: \(keepingAlive ? "keep-alive" : "close")\r\n\r\n"
        return Data(head.utf8) + body
    }

    static let continueInterim = Data("HTTP/1.1 100 Continue\r\n\r\n".utf8)

    private static func reason(for status: Int) -> String {
        reasons[status] ?? "Status"
    }

    private static let reasons = [
        200: "OK",
        202: "Accepted",
        400: "Bad Request",
        401: "Unauthorized",
        403: "Forbidden",
        404: "Not Found",
        405: "Method Not Allowed",
        413: "Content Too Large",
        431: "Request Header Fields Too Large",
        500: "Internal Server Error",
        501: "Not Implemented",
        503: "Service Unavailable"
    ]
}

/// Reads requests from the bytes received on a connection so far.
enum HTTPRequestParser {
    enum Outcome: Equatable {
        /// More bytes are needed. Once the headers are in, says whether the client waits for `100 Continue`.
        case incomplete(expectsContinue: Bool)
        /// A request, and how many bytes of the buffer it took.
        case complete(HTTPRequest, consumedBytes: Int)
        /// The connection should get this status and be closed.
        case invalid(status: Int)
    }

    /// Agents send small JSON messages; anything far larger is not one.
    static let maximumHeaderBytes = 32 * 1_024
    static let maximumBodyBytes = 4 * 1_024 * 1_024

    private static let headerEnd = Data("\r\n\r\n".utf8)

    static func parse(_ buffer: Data) -> Outcome {
        guard let end = buffer.firstRange(of: headerEnd) else {
            return buffer.count > maximumHeaderBytes ? .invalid(status: 431) : .incomplete(expectsContinue: false)
        }
        let headBytes = end.lowerBound - buffer.startIndex
        guard headBytes <= maximumHeaderBytes else {
            return .invalid(status: 431)
        }
        guard let head = String(data: buffer[buffer.startIndex..<end.lowerBound], encoding: .utf8) else {
            return .invalid(status: 400)
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else {
            return .invalid(status: 400)
        }
        guard let headers = parseHeaders(lines) else {
            return .invalid(status: 400)
        }
        // Chunked bodies are not needed by MCP clients, which send each message with its length.
        if headers["transfer-encoding"] != nil {
            return .invalid(status: 501)
        }
        let length: Int
        if let declared = headers["content-length"] {
            guard let value = Int(declared), value >= 0 else {
                return .invalid(status: 400)
            }
            length = value
        } else {
            length = 0
        }
        guard length <= maximumBodyBytes else {
            return .invalid(status: 413)
        }
        let bodyStart = end.upperBound
        guard buffer.endIndex - bodyStart >= length else {
            let expectsContinue = headers["expect"]?.lowercased() == "100-continue"
            return .incomplete(expectsContinue: expectsContinue)
        }
        let target = String(requestLine[1])
        let request = HTTPRequest(
            method: String(requestLine[0]).uppercased(),
            path: String(target.prefix { $0 != "?" }),
            headers: headers,
            body: Data(buffer[bodyStart..<(bodyStart + length)])
        )
        return .complete(request, consumedBytes: bodyStart + length - buffer.startIndex)
    }

    private static func parseHeaders(_ lines: [String]) -> [String: String]? {
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else {
                return nil
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty, !name.contains(" ") else {
                return nil
            }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return headers
    }
}
