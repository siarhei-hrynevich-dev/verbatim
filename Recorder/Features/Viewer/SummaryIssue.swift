import Foundation

/// Why summarizing failed, as the user reads it. Trying again is always offered; this says when Settings has to change
/// something first.
struct SummaryIssue: Equatable, Sendable {
    let title: String
    let message: String
    let needsSettings: Bool

    init(_ failure: SummaryFailure) {
        switch failure {
        case .noModelSelected:
            title = String(localized: "No summary model selected")
            message = String(localized: "Download or select one in Settings › AI Models › Summaries.")
            needsSettings = true
        case .modelUnavailable:
            title = String(localized: "The summary model isn’t available")
            message = String(localized: "Its files are missing or damaged. Repair it in Settings › AI Models.")
            needsSettings = true
        case .modelLoadFailed(let detail):
            title = String(localized: "The summary model couldn’t be loaded")
            message = String(localized: "Try again, or choose another model in Settings. \(detail)")
            needsSettings = true
        case .noTranscript:
            title = String(localized: "There’s no transcript yet")
            message = String(localized: "Summaries are made from the transcript. Generate one first.")
            needsSettings = false
        case .emptyTranscript:
            title = String(localized: "There’s nothing to summarize")
            message = String(localized: "No speech was found in this recording.")
            needsSettings = false
        case .generationFailed(let detail):
            title = String(localized: "Summarizing failed")
            message = String(localized: "The transcript is intact. \(detail)")
            needsSettings = false
        case .persistenceFailed(let detail):
            title = String(localized: "The summary couldn’t be saved")
            message = String(localized: "Any earlier summary is intact. \(detail)")
            needsSettings = false
        }
    }
}
