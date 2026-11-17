import Foundation

/// Why a recording cannot play, as the user reads it, with what they can do about it.
struct ViewerIssue: Equatable, Sendable {
    enum Recovery: Equatable, Sendable {
        case retry
        case locateFile
        case showInFinder
    }

    let title: String
    let message: String
    /// Most useful first.
    let recoveries: [Recovery]

    init(title: String, message: String, recoveries: [Recovery]) {
        self.title = title
        self.message = message
        self.recoveries = recoveries
    }

    init(_ failure: PlaybackFailure) {
        switch failure {
        case .recordingNotFound:
            self.init(
                title: String(localized: "This recording is no longer in the Library"),
                message: String(localized: "It was removed or deleted. Return to the Library to choose another."),
                recoveries: []
            )
        case .mediaUnavailable(let availability):
            self = Self.unavailable(availability)
        case .unsupportedFormat:
            self.init(
                title: String(localized: "This file can’t be played"),
                message: String(localized: "This Mac can’t decode its format. The file itself wasn’t changed."),
                recoveries: [.showInFinder, .locateFile]
            )
        case .corruptedMedia:
            self.init(
                title: String(localized: "This file seems to be damaged"),
                message: String(localized: "It couldn’t be read as a recording. The file itself wasn’t changed."),
                recoveries: [.showInFinder, .locateFile, .retry]
            )
        case .loadFailed, .seekFailed:
            self.init(
                title: String(localized: "The recording couldn’t be opened"),
                message: String(localized: "Something went wrong while preparing it. The file itself wasn’t changed."),
                recoveries: [.retry, .showInFinder]
            )
        case .playbackFailed:
            self.init(
                title: String(localized: "Playback stopped"),
                message: String(localized: "Something went wrong while playing. The file itself wasn’t changed."),
                recoveries: [.retry, .showInFinder]
            )
        }
    }

    private static func unavailable(_ availability: MediaAvailability) -> ViewerIssue {
        switch availability {
        case .volumeUnavailable:
            ViewerIssue(
                title: String(localized: "The drive isn’t connected"),
                message: String(localized: "Connect the drive holding this recording, then try again."),
                recoveries: [.retry, .locateFile]
            )
        case .accessDenied:
            ViewerIssue(
                title: String(localized: "Verbatim doesn’t have access to this file"),
                message: String(localized: "Use Locate File to choose it and grant access."),
                recoveries: [.locateFile, .retry]
            )
        case .missing, .available:
            ViewerIssue(
                title: String(localized: "The file is missing"),
                message: String(localized: "It may have been moved or deleted in Finder. Use Locate File to find it."),
                recoveries: [.locateFile, .retry]
            )
        }
    }
}

extension ViewerIssue.Recovery {
    var title: String {
        switch self {
        case .retry: String(localized: "Try Again")
        case .locateFile: String(localized: "Locate File…")
        case .showInFinder: String(localized: "Show in Finder")
        }
    }
}
