import Foundation

/// What the Viewer's side panel shows.
enum ViewerPanelMode: Hashable {
    case transcript
    case summary
}

/// Summarizing the open recording, while it is under way or after it failed.
enum ViewerSummaryActivity: Equatable {
    case queued
    case loadingModel
    case writingParts(completed: Int, total: Int)
    case combining
    case saving
    case stopping
    case failed(SummaryIssue)
}

/// The open recording's summary: reading it, asking for one, and following the work.
extension ViewerViewModel {
    /// Summaries need the real Library and a transcript with speech; design scenarios have none.
    var canSummarize: Bool {
        guard !isPreviewing, summaries != nil, let storedTranscript else {
            return false
        }
        return !storedTranscript.segments.isEmpty
    }

    var summaryActivity: ViewerSummaryActivity? {
        guard !isPreviewing, let summaries, let id = recordingID, let job = summaries.job(for: id) else {
            return nil
        }
        if summaries.isStopping(id) {
            return .stopping
        }
        switch job.state {
        case .queued: return .queued
        case .loadingModel: return .loadingModel
        case .summarizingParts(let completed, let total): return .writingParts(completed: completed, total: total)
        case .combining: return .combining
        case .saving: return .saving
        case .failed(let failure): return .failed(SummaryIssue(failure))
        }
    }

    /// The transcript was made again after this summary.
    var isSummaryOutdated: Bool {
        guard let summary, let storedTranscript else {
            return false
        }
        return !summary.isCurrent(for: storedTranscript)
    }

    /// Why the shown summary no longer matches what Summarize would write now, if it doesn't.
    var summaryStaleness: String? {
        guard let summary else {
            return nil
        }
        if isSummaryOutdated {
            return String(localized: "The transcript changed after this summary was written.")
        }
        guard let summaries, let code = summary.language, code != summaries.language.code else {
            return nil
        }
        let written = TranscriptionLanguage.displayName(forCode: code)
        return String(
            localized: "This summary is in \(written). Summaries are now written in \(summaries.language.title)."
        )
    }

    var summaryActionTitle: String {
        summary == nil ? String(localized: "Summarize") : String(localized: "Summarize Again")
    }

    func generateSummary() {
        guard canSummarize, let recordingID else {
            return
        }
        summaries?.enqueue(recordingID)
    }

    func cancelSummary() {
        if let recordingID {
            summaries?.cancel(recordingID)
        }
    }

    func dismissSummaryFailure() {
        if let recordingID {
            summaries?.dismissFailure(of: recordingID)
        }
    }

    /// Reads the stored summary when this session has not yet, or when a new one has been stored since.
    func reloadSummaryIfNeeded() async {
        guard !isPreviewing, let summaries, let id = recordingID else {
            return
        }
        let revision = summaries.revision
        guard revision != loadedSummaryRevision else {
            return
        }
        do {
            let stored = try await summaries.summary(for: id)
            guard !Task.isCancelled, id == recordingID else {
                return
            }
            loadedSummaryRevision = revision
            summary = stored
        } catch {
            Self.logger.error("Could not read a summary: \(String(describing: error))")
        }
    }

    func forgetSummary() {
        summary = nil
        loadedSummaryRevision = nil
    }

    /// Plays from where a summary part begins.
    func seek(toPart part: SummaryPart) {
        seek(to: part.startTime)
    }

    /// The summary as text for the clipboard, followed by the notes on each part.
    var summaryText: String {
        guard let summary else {
            return ""
        }
        let parts = summary.parts.map {
            "\(RecordingClock.timerText(for: $0.startTime))–\(RecordingClock.timerText(for: $0.endTime))\n\($0.text)"
        }
        return ([summary.text] + parts).joined(separator: "\n\n")
    }
}
