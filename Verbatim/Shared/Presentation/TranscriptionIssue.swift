import Foundation

/// Why transcribing failed, as the user reads it, in the Library and the Viewer alike. Retrying is always offered; this
/// says when something else has to change first.
struct TranscriptionIssue: Equatable, Sendable {
    enum Recovery: Equatable, Sendable {
        case retry
        case openSettings
    }

    let title: String
    let message: String
    let recovery: Recovery

    init(title: String, message: String, recovery: Recovery = .retry) {
        self.title = title
        self.message = message
        self.recovery = recovery
    }

    init(_ failure: TranscriptionFailure) {
        switch failure {
        case .noModelSelected, .modelUnavailable, .modelLoadFailed:
            self = Self.model(failure)
        case .mediaUnavailable, .recordingNotFound:
            self = Self.media(failure)
        case .noAudio:
            self.init(
                title: String(localized: "This recording has no audio"),
                message: String(localized: "There’s nothing to transcribe, because it was recorded without sound.")
            )
        case .unsupportedAudio(let detail):
            self.init(
                title: String(localized: "This audio can’t be read"),
                message: String(localized: "Its format isn’t supported. The recording wasn’t changed. \(detail)")
            )
        case .audioExtractionFailed(let detail):
            self.init(
                title: String(localized: "The audio couldn’t be decoded"),
                message: String(localized: "The file may be damaged. The recording wasn’t changed. \(detail)")
            )
        case .recognitionFailed(let detail):
            self.init(
                title: String(localized: "Transcription failed"),
                message: String(localized: "The recording is intact and plays normally. \(detail)")
            )
        case .insufficientDiskSpace(let required, _):
            let size = required.formatted(.byteCount(style: .file))
            self.init(
                title: String(localized: "Not enough disk space"),
                message: String(localized: "Free up at least \(size), then try again. The recording is intact.")
            )
        case .persistenceFailed(let detail):
            self.init(
                title: String(localized: "The transcript couldn’t be saved"),
                message: String(localized: "Any earlier transcript and the recording are intact. \(detail)")
            )
        }
    }

    private static func model(_ failure: TranscriptionFailure) -> TranscriptionIssue {
        switch failure {
        case .noModelSelected:
            TranscriptionIssue(
                title: String(localized: "No speech model is selected"),
                message: String(localized: "Download and select one in Settings › AI Models, then try again."),
                recovery: .openSettings
            )
        case .modelUnavailable:
            TranscriptionIssue(
                title: String(localized: "The selected model isn’t available"),
                message: String(
                    localized: "Its files are missing or damaged. Repair it in Settings › AI Models, or select another."
                ),
                recovery: .openSettings
            )
        default:
            TranscriptionIssue(
                title: String(localized: "The speech model couldn’t be loaded"),
                message: String(localized: "Try again, or select another model in Settings › AI Models."),
                recovery: .openSettings
            )
        }
    }

    private static func media(_ failure: TranscriptionFailure) -> TranscriptionIssue {
        switch failure {
        case .mediaUnavailable(.volumeUnavailable):
            TranscriptionIssue(
                title: String(localized: "The drive isn’t connected"),
                message: String(localized: "Connect the drive holding this recording, then try again.")
            )
        case .mediaUnavailable(.accessDenied):
            TranscriptionIssue(
                title: String(localized: "Verbatim doesn’t have access to this file"),
                message: String(localized: "Use Locate File to choose it and grant access, then try again.")
            )
        default:
            TranscriptionIssue(
                title: String(localized: "The recording’s file is missing"),
                message: String(localized: "It may have been moved or deleted in Finder. Locate it, then try again.")
            )
        }
    }
}

extension TranscriptionLanguage {
    /// The languages to choose from, by name in the user's language.
    static let choices: [TranscriptionLanguage] =
        supportedCodes
        .map { TranscriptionLanguage.explicit(code: $0) }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

    var title: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .explicit(let code): Self.displayName(forCode: code)
        }
    }

    static func displayName(forCode code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized(with: .current) ?? code
    }
}
