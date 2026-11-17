import Foundation

/// A link to a moment in a recording, `verbatim://recording/<id>?t=<seconds>`, which opens the Viewer there. AI agents
/// cite recordings with these, so the scheme and layout must stay stable.
struct RecordingLink: Equatable, Sendable {
    static let scheme = "verbatim"
    private static let host = "recording"
    private static let timeItem = "t"

    let recordingID: UUID
    /// Seconds on the recording's own timeline; `nil` opens it from the start.
    let time: TimeInterval?

    init(recordingID: UUID, time: TimeInterval? = nil) {
        self.recordingID = recordingID
        self.time = time.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }

    /// `nil` for anything that is not such a link, or names no valid recording identifier.
    init?(url: URL) {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == Self.scheme,
            components.host?.lowercased() == Self.host
        else {
            return nil
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let id = UUID(uuidString: path) else {
            return nil
        }
        let time = components.queryItems?.first { $0.name == Self.timeItem }?.value.flatMap(TimeInterval.init)
        self.init(recordingID: id, time: time)
    }

    /// Whole seconds are enough to find a moment, and keep links short.
    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.path = "/" + recordingID.uuidString
        if let time {
            components.queryItems = [URLQueryItem(name: Self.timeItem, value: String(Int(time.rounded(.down))))]
        }
        // Every part is set from validated values above, which always form a URL.
        return components.url ?? URL(filePath: "/")
    }
}
