import Foundation

/// Why a recording cannot be played. User-facing wording belongs to Presentation.
enum PlaybackFailure: Error, Equatable, Sendable {
    /// The Library no longer has an entry for the recording.
    case recordingNotFound
    case mediaUnavailable(MediaAvailability)
    /// The file is intact as far as can be told, but this Mac cannot decode it.
    case unsupportedFormat
    case corruptedMedia
    case loadFailed(detail: String)
    /// Playback started and then stopped working.
    case playbackFailed(detail: String)
    case seekFailed
}

extension PlaybackFailure {
    /// Translates what the Library or the playback engine reported.
    init(_ error: any Error) {
        switch error {
        case let failure as PlaybackFailure:
            self = failure
        case LibraryError.recordingNotFound:
            self = .recordingNotFound
        case LibraryError.mediaUnavailable(let availability):
            self = .mediaUnavailable(availability)
        case LibraryError.corruptedMedia:
            self = .corruptedMedia
        default:
            self = .loadFailed(detail: String(describing: error))
        }
    }
}

/// One playback session's lifecycle. Only `ViewerViewModel` advances it, through `allowsTransition(to:)`.
enum PlaybackState: Equatable, Sendable {
    case idle
    case loading
    /// Loaded and at its starting position; nothing has played or moved yet.
    case ready
    case playing
    case paused
    case ended
    case failed(PlaybackFailure)

    /// Whether media is loaded, so that the transport controls can act on it.
    var isLoaded: Bool {
        switch self {
        case .ready, .playing, .paused, .ended: true
        case .idle, .loading, .failed: false
        }
    }

    func allowsTransition(to next: PlaybackState) -> Bool {
        switch (self, next) {
        // A session can be closed or replaced from any state.
        case (_, .idle), (_, .loading):
            true
        case (.loading, .ready), (.loading, .failed), (.failed, .failed):
            true
        case (.ready, .playing), (.ready, .paused), (.ready, .ended), (.ready, .failed),
            (.playing, .paused), (.playing, .ended), (.playing, .failed),
            (.paused, .playing), (.paused, .ended), (.paused, .failed),
            (.ended, .playing), (.ended, .paused), (.ended, .failed):
            true
        default:
            false
        }
    }
}

/// How closely a seek must land. Approximate seeks stop at a nearby frame that decodes quickly, for scrubbing.
enum PlaybackSeekPrecision: Sendable {
    case exact
    case approximate
}

/// What the media file itself says, as opposed to what the Library stored about it.
struct PlaybackMediaInfo: Equatable, Sendable {
    let duration: TimeInterval
    let hasVideo: Bool
    let audioTrackCount: Int
}

/// What happens during playback without anyone asking for it.
enum PlaybackEvent: Equatable, Sendable {
    /// The playhead moved, in seconds from the start of the media.
    case timeChanged(TimeInterval)
    /// Playback stopped for a reason other than reaching the end.
    case paused
    case playedToEnd
    case failed(PlaybackFailure)
}

/// The rules for positions on a recording's timeline.
enum PlaybackTimeline {
    /// Within this many seconds of the end counts as the end: the last frame starts slightly before the duration.
    static let endToleranceSeconds: TimeInterval = 0.05
    /// Container and track durations differ by a few frames normally, which is not worth reporting.
    static let durationMismatchToleranceSeconds: TimeInterval = 1

    /// A position within the recording, or `nil` for one that is not a number.
    static func validatedPosition(_ seconds: TimeInterval, duration: TimeInterval) -> TimeInterval? {
        guard seconds.isFinite, duration.isFinite else {
            return nil
        }
        return min(max(seconds, 0), max(duration, 0))
    }

    static func isAtEnd(_ position: TimeInterval, duration: TimeInterval) -> Bool {
        duration > 0 && position >= duration - endToleranceSeconds
    }

    /// Playback runs on the media's real length. The stored duration only stands in until the file has been read, or
    /// if the file cannot report a usable length.
    static func effectiveDuration(media: TimeInterval?, stored: TimeInterval) -> TimeInterval {
        guard let media, media.isFinite, media > 0 else {
            return stored
        }
        return media
    }

    static func durationsDisagree(media: TimeInterval, stored: TimeInterval) -> Bool {
        abs(media - stored) > durationMismatchToleranceSeconds
    }
}
