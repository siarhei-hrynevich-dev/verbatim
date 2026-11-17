import Foundation

/// The MCP tools: reads their arguments, asks `RecordingKnowledgeService`, and returns what it found as a tool result.
/// A problem an agent can correct, such as an unknown identifier, comes back as a tool error with advice, so the agent
/// sees it and can try again.
struct MCPToolbox: Sendable {
    let knowledge: RecordingKnowledgeService
    var now: @Sendable () -> Date = { .now }
    /// Dates in arguments without an offset, and dates in results, are in this zone.
    var timeZone = TimeZone.current

    static let defaultTranscriptCharacters = 8_000
    static let maximumTranscriptCharacters = 40_000
    static let defaultContextSeconds: TimeInterval = 60

    /// Returns a `CallToolResult`.
    func call(_ name: String, arguments: JSONValue) async -> JSONValue {
        do {
            let output: JSONValue
            switch name {
            case MCPToolName.search: output = try await search(decode(arguments))
            case MCPToolName.list: output = try await list(decode(arguments))
            case MCPToolName.recording: output = try await recording(decode(arguments))
            case MCPToolName.summary: output = try await summary(decode(arguments))
            case MCPToolName.transcript: output = try await transcript(decode(arguments))
            case MCPToolName.tags: output = try await convert(MCPToolOutput.tags(knowledge.tagUsage()))
            default: return Self.toolError("Unknown tool: \(name)")
            }
            return try Self.success(output)
        } catch let error as MCPArgumentError {
            return Self.toolError(error.message)
        } catch let error as RecordingKnowledgeError {
            return Self.toolError(Self.message(for: error))
        } catch {
            return Self.toolError("The request could not be completed: \(error.localizedDescription)")
        }
    }

    // MARK: - Tools

    private func search(_ arguments: SearchArguments) async throws -> JSONValue {
        let query = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw MCPArgumentError("`query` must not be empty.")
        }
        let kinds = try arguments.sources.map { names in
            Set(try names.map(Self.chunkKind))
        }
        let result = try await knowledge.search(
            query,
            filter: try filter(from: arguments.from, to: arguments.until, tags: arguments.tags),
            recordingIDs: try arguments.recordingIds.map { Set(try $0.map(Self.recordingID)) },
            kinds: kinds,
            limit: arguments.limit ?? 10
        )
        return try convert(MCPToolOutput.search(result, now: now()))
    }

    private func list(_ arguments: ListArguments) async throws -> JSONValue {
        var request = RecordingListRequest(
            filter: try filter(from: arguments.from, to: arguments.until, tags: arguments.tags),
            titleText: arguments.title,
            limit: arguments.limit ?? 20
        )
        request.captureModes = try Self.captureModes(arguments.type)
        request.sortOrder = try Self.sortOrder(arguments.sort)
        if let cursor = arguments.cursor {
            guard let offset = Int(cursor), offset >= 0 else {
                throw MCPArgumentError("Invalid `cursor`: pass `next_cursor` from the previous page unchanged.")
            }
            request.offset = offset
        }
        let page = try await knowledge.listRecordings(request)
        return try convert(
            MCPToolOutput.RecordingList(
                now: now(),
                totalCount: page.totalCount,
                nextCursor: page.nextOffset.map(String.init),
                recordings: page.recordings.map(MCPToolOutput.recording)
            )
        )
    }

    private func recording(_ arguments: RecordingArguments) async throws -> JSONValue {
        let details = try await knowledge.details(of: Self.recordingID(arguments.recordingId))
        return try convert(MCPToolOutput.details(details))
    }

    private func summary(_ arguments: RecordingArguments) async throws -> JSONValue {
        let summary = try await knowledge.summary(of: Self.recordingID(arguments.recordingId))
        return try convert(MCPToolOutput.summary(summary))
    }

    private func transcript(_ arguments: TranscriptArguments) async throws -> JSONValue {
        let window: TranscriptWindow
        if let chunkID = arguments.aroundChunkId {
            guard arguments.from == nil, arguments.until == nil else {
                throw MCPArgumentError("Give either `around_chunk_id` or `from`/`to`, not both.")
            }
            window = .aroundChunk(chunkID, contextSeconds: arguments.contextSeconds ?? Self.defaultContextSeconds)
        } else {
            window = .range(start: arguments.from, end: arguments.until)
        }
        let characters = min(
            max(arguments.maxCharacters ?? Self.defaultTranscriptCharacters, 200),
            Self.maximumTranscriptCharacters
        )
        let excerpt = try await knowledge.transcript(
            of: Self.recordingID(arguments.recordingId),
            window: window,
            maximumCharacters: characters
        )
        return try convert(MCPToolOutput.transcript(excerpt))
    }

    // MARK: - Arguments

    private func decode<Arguments: Decodable>(_ arguments: JSONValue) throws -> Arguments {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(Arguments.self, from: arguments.encoded())
        } catch let error as DecodingError {
            throw MCPArgumentError("Invalid arguments: \(Self.describe(error))")
        }
    }

    private func filter(from start: String?, to end: String?, tags: [String]?) throws -> RecordingKnowledgeFilter {
        let dates = MCPDateArgument(now: now(), timeZone: timeZone)
        return RecordingKnowledgeFilter(
            createdFrom: try start.map { try dates.start(of: $0, argument: "from") },
            createdBefore: try end.map { try dates.end(of: $0, argument: "to") },
            tagNames: tags ?? []
        )
    }

    private static func captureModes(_ type: String?) throws -> [CaptureMode] {
        switch type {
        case nil: return []
        case "video": return [.screen, .window]
        case "audio": return [.audioOnly]
        case let other?: throw MCPArgumentError("Unknown `type` \"\(other)\": use \"video\" or \"audio\".")
        }
    }

    private static func sortOrder(_ name: String?) throws -> RecordingSortOrder {
        switch name {
        case nil, "newest": return .newestFirst
        case "oldest": return .oldestFirst
        case "longest": return .duration
        case "title": return .name
        case let other?: throw MCPArgumentError("Unknown `sort` \"\(other)\": use newest, oldest, longest or title.")
        }
    }

    private static func recordingID(_ text: String) throws -> UUID {
        guard let id = UUID(uuidString: text.trimmingCharacters(in: .whitespaces)) else {
            throw MCPArgumentError("\"\(text)\" is not a recording id. Ids look like \(UUID().uuidString).")
        }
        return id
    }

    private static func chunkKind(_ name: String) throws -> SearchChunkKind {
        guard let kind = SearchChunkKind(rawValue: name) else {
            throw MCPArgumentError("Unknown source \"\(name)\": use transcript, summary or summary_part.")
        }
        return kind
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, _):
            return "missing `\(key.stringValue.snakeCased)`"
        case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
            let path = context.codingPath.map(\.stringValue.snakeCased).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "`\(path)` has the wrong type"
        @unknown default:
            return String(describing: error)
        }
    }

    // MARK: - Results

    private func convert<Value: Encodable>(_ value: Value) throws -> JSONValue {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let timeZone = timeZone
        // `ISO8601FormatStyle` writes offsets as +0100; RFC 3339, which agents expect, has +01:00.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = timeZone
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return try JSONValue.converting(value, with: encoder)
    }

    /// The text block repeats the structured content for clients that read only text.
    private static func success(_ output: JSONValue) throws -> JSONValue {
        // JSONEncoder always writes UTF-8.
        guard let text = String(bytes: try output.encoded(), encoding: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }
        return ["content": [["type": "text", "text": .string(text)]], "structuredContent": output, "isError": false]
    }

    private static func toolError(_ message: String) -> JSONValue {
        ["content": [["type": "text", "text": .string(message)]], "isError": true]
    }

    static func message(for error: RecordingKnowledgeError) -> String {
        switch error {
        case .recordingNotFound(let id):
            "No recording has id \(id.uuidString). Find ids with list_recordings or search_recordings."
        case let .unknownTags(names, available):
            "Unknown tags: \(names.joined(separator: ", ")). Tags in Verbatim: "
                + (available.isEmpty ? "none." : available.joined(separator: ", ") + ".")
        case let .transcriptUnavailable(id, status):
            "Recording \(id.uuidString) has no transcript (\(statusDescription(status)))."
        case let .summaryUnavailable(id, status):
            "Recording \(id.uuidString) has no summary (\(statusDescription(status))). Read get_transcript instead."
        case .chunkNotFound(let id):
            "No search result has chunk id \(id); the recording may have been indexed again. Search again."
        case let .chunkInOtherRecording(chunkID, recordingID):
            "Chunk \(chunkID) belongs to recording \(recordingID.uuidString); pass that as `recording_id`."
        case .chunkWithoutTime(let id):
            "Chunk \(id) is the whole summary and has no place on the timeline; read it with get_summary."
        case .invalidTimeRange:
            "`from` must be zero or more, and less than `to`."
        case .storageFailed(let detail):
            "Verbatim could not read its library: \(detail)"
        }
    }

    private static func statusDescription(_ status: PipelineStepStatus) -> String {
        switch status {
        case .ready: "it is being replaced"
        case .queued: "it is queued; try again later"
        case .running: "it is being made now; try again in a few minutes"
        case .failed: "making it failed; the user can retry in Verbatim"
        case .none: "none was made; the user can start it in Verbatim, which needs a model selected in Settings"
        }
    }
}

/// A mistake in a tool's arguments, explained to the agent.
struct MCPArgumentError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

extension String {
    /// `recordingId` as `recording_id`, for naming arguments as the agent wrote them.
    fileprivate var snakeCased: String {
        reduce(into: "") { result, character in
            if character.isUppercase {
                result += "_" + character.lowercased()
            } else {
                result.append(character)
            }
        }
    }
}

// MARK: - Arguments

/// Arguments as agents send them, in snake_case. Unknown keys are ignored.
private struct SearchArguments: Decodable {
    let query: String
    var from: String?
    var until: String?
    var tags: [String]?
    var recordingIds: [String]?
    var sources: [String]?
    var limit: Int?

    /// Keys after snake_case conversion. `to` is read into `until`, as names must be three letters or longer.
    enum CodingKeys: String, CodingKey {
        case query, from, tags, recordingIds, sources, limit
        case until = "to"
    }
}

private struct ListArguments: Decodable {
    var from: String?
    var until: String?
    var tags: [String]?
    var title: String?
    var type: String?
    var sort: String?
    var limit: Int?
    var cursor: String?

    enum CodingKeys: String, CodingKey {
        case from, tags, title, type, sort, limit, cursor
        case until = "to"
    }
}

private struct RecordingArguments: Decodable {
    let recordingId: String
}

private struct TranscriptArguments: Decodable {
    let recordingId: String
    var from: Double?
    var until: Double?
    var aroundChunkId: Int64?
    var contextSeconds: Double?
    var maxCharacters: Int?

    enum CodingKeys: String, CodingKey {
        case recordingId, from, aroundChunkId, contextSeconds, maxCharacters
        case until = "to"
    }
}
