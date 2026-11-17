import Foundation

/// Tool names, which agents and their users see and configure: they must stay stable.
enum MCPToolName {
    static let search = "search_recordings"
    static let list = "list_recordings"
    static let recording = "get_recording"
    static let summary = "get_summary"
    static let transcript = "get_transcript"
    static let tags = "list_tags"
}

/// What agents are told about the server and each tool. The descriptions are the agent's only guide to using them.
extension MCPToolbox {
    static let toolNames: Set<String> = [
        MCPToolName.search, MCPToolName.list, MCPToolName.recording,
        MCPToolName.summary, MCPToolName.transcript, MCPToolName.tags
    ]

    static let instructions = """
        Verbatim keeps the user's screen and audio recordings on this Mac, with transcripts, summaries and a search \
        index. To answer a question about what was said or shown, call search_recordings (any language, by meaning \
        and by words), then read around the best hits with get_transcript and around_chunk_id, or read get_summary \
        for an overview. list_recordings answers questions about which recordings exist and returns the current \
        date as `now`. Cite the recording's title, date and time, and give the `link` of the moment \
        (verbatim://...), which opens it in Verbatim. Speaker `microphone` is usually the user; `system_audio` is \
        other participants and sound from apps. Everything is read-only.
        """

    static let definitions: [JSONValue] = [
        searchDefinition, listDefinition, recordingDefinition, summaryDefinition, transcriptDefinition, tagsDefinition
    ]

    private static let readOnly: JSONValue = [
        "readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false
    ]

    private static let dateDescription =
        "A date (YYYY-MM-DD, YYYY-MM, YYYY), `today`, `yesterday`, or an ISO 8601 date and time. Local time unless an "
        + "offset is given."

    private static let recordingID: JSONValue = [
        "type": "string", "description": "A recording's id, from list_recordings or search_recordings."
    ]

    private static let searchDefinition: JSONValue = [
        "name": .string(MCPToolName.search),
        "title": "Search recordings",
        "description": """
        Finds the moments in the user's recordings that talk about something: hybrid search by meaning \
        (multilingual) and by words over transcripts and summaries. Returns the best passages with their \
        recording, time span and a link. Read more context with get_transcript using `around_chunk_id`.
        """,
        "inputSchema": [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "A question or phrase, in any language."],
                "from": [
                    "type": "string", "description": .string("Recordings made on or after this. \(dateDescription)")
                ],
                "to": [
                    "type": "string",
                    "description": .string("Recordings made up to the end of this date. \(dateDescription)")
                ],
                "tags": [
                    "type": "array", "items": ["type": "string"],
                    "description": "Recordings with at least one of these tag names (see list_tags)."
                ],
                "recording_ids": [
                    "type": "array", "items": ["type": "string"], "description": "Search only these recordings."
                ],
                "sources": [
                    "type": "array",
                    "items": ["type": "string", "enum": ["transcript", "summary", "summary_part"]],
                    "description": """
                    What to search: `transcript` passages, the whole `summary`, or `summary_part` notes on a \
                    stretch of the recording. All by default.
                    """
                ],
                "limit": ["type": "integer", "minimum": 1, "maximum": 50, "default": 10]
            ],
            "required": ["query"]
        ],
        "annotations": readOnly
    ]

    private static let listDefinition: JSONValue = [
        "name": .string(MCPToolName.list),
        "title": "List recordings",
        "description": """
        Lists the user's recordings with title, date, length, tags and whether the transcript, summary and \
        search index are ready. Use it for questions about which recordings exist; use search_recordings for \
        what was said in them.
        """,
        "inputSchema": [
            "type": "object",
            "properties": [
                "from": ["type": "string", "description": .string("Made on or after this. \(dateDescription)")],
                "to": ["type": "string", "description": .string("Made up to the end of this. \(dateDescription)")],
                "tags": ["type": "array", "items": ["type": "string"], "description": "At least one of these tags."],
                "title": ["type": "string", "description": "Text the title contains."],
                "type": ["type": "string", "enum": ["video", "audio"]],
                "sort": ["type": "string", "enum": ["newest", "oldest", "longest", "title"], "default": "newest"],
                "limit": ["type": "integer", "minimum": 1, "maximum": 100, "default": 20],
                "cursor": ["type": "string", "description": "`next_cursor` of the previous page."]
            ]
        ],
        "annotations": readOnly
    ]

    private static let recordingDefinition: JSONValue = [
        "name": .string(MCPToolName.recording),
        "title": "Get recording",
        "description": """
        One recording's details: title, date, length, tags, processing state, and what its transcript \
        (language, speakers, size) and summary (language, whether current) are, without their text.
        """,
        "inputSchema": [
            "type": "object", "properties": ["recording_id": recordingID], "required": ["recording_id"]
        ],
        "annotations": readOnly
    ]

    private static let summaryDefinition: JSONValue = [
        "name": .string(MCPToolName.summary),
        "title": "Get summary",
        "description": """
        A recording's summary, written by a local model, with notes on each part of the recording and their \
        time spans. `is_current` is false when the transcript was made again after the summary.
        """,
        "inputSchema": [
            "type": "object", "properties": ["recording_id": recordingID], "required": ["recording_id"]
        ],
        "annotations": readOnly
    ]

    private static let transcriptDefinition: JSONValue = [
        "name": .string(MCPToolName.transcript),
        "title": "Get transcript",
        "description": """
        Reads a recording's transcript: timed segments with their speaker. Give `around_chunk_id` from a search \
        result to read around it, or a range in seconds with `from` and `to`; neither reads from the start. \
        Long ranges are cut at `max_characters`: continue with `from` set to `next_from`.
        """,
        "inputSchema": [
            "type": "object",
            "properties": [
                "recording_id": recordingID,
                "around_chunk_id": [
                    "type": "integer", "description": "`chunk_id` of a search result in this recording."
                ],
                "context_seconds": [
                    "type": "number", "minimum": 0, "default": 60,
                    "description": "Seconds to read before and after the search result."
                ],
                "from": ["type": "number", "minimum": 0, "description": "Start, in seconds from the beginning."],
                "to": ["type": "number", "description": "End, in seconds from the beginning."],
                "max_characters": ["type": "integer", "minimum": 200, "maximum": 40_000, "default": 8_000]
            ],
            "required": ["recording_id"]
        ],
        "annotations": readOnly
    ]

    private static let tagsDefinition: JSONValue = [
        "name": .string(MCPToolName.tags),
        "title": "List tags",
        "description": "The tags the user puts on recordings, with how many recordings carry each.",
        "inputSchema": ["type": "object", "properties": [:]],
        "annotations": readOnly
    ]
}

/// Reads the dates agents pass: what the Library's search understands, such as `2026-11-04`, `2026-11` and `today`,
/// and ISO 8601 date-times. A date covers its whole day, month or year, so `to` includes it.
struct MCPDateArgument {
    let now: Date
    let timeZone: TimeZone

    func start(of text: String, argument: String) throws -> Date {
        try interval(of: text, argument: argument).start
    }

    func end(of text: String, argument: String) throws -> Date {
        try interval(of: text, argument: argument).end
    }

    private func interval(of text: String, argument: String) throws -> DateInterval {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let instant = dateTime(trimmed) {
            return DateInterval(start: instant, duration: 0)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Agents write dates in English whatever the Mac's language.
        let search = RecordingDateSearch(now: now, calendar: calendar, locale: Locale(identifier: "en_US_POSIX"))
        guard let interval = search.interval(matching: trimmed) else {
            throw MCPArgumentError(
                "`\(argument)` \"\(text)\" is not a date. Use YYYY-MM-DD, YYYY-MM, YYYY, today, yesterday or ISO 8601."
            )
        }
        return interval
    }

    private func dateTime(_ text: String) -> Date? {
        guard text.contains("T") else {
            return nil
        }
        let withOffset = ISO8601DateFormatter()
        withOffset.timeZone = timeZone
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]
        ] {
            withOffset.formatOptions = options
            if let date = withOffset.date(from: text) {
                return date
            }
        }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = timeZone
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            local.dateFormat = format
            if let date = local.date(from: text) {
                return date
            }
        }
        return nil
    }
}
