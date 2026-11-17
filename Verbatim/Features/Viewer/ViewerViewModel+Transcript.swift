import Foundation

/// A real recording's transcript: reading it from storage, what is being done to it, and getting it out of the app.
extension ViewerViewModel {
    var transcriptActivity: ViewerTranscriptActivity? {
        guard !isPreviewing, let processing, let id = recordingID, let job = processing.job(for: id) else {
            return nil
        }
        if processing.isStopping(id) {
            return .stopping
        }
        switch job.state {
        case .pending: return .queued
        case .preparing: return .running(.preparingModel)
        case .transcribing: return .running(.processingAudio(progress: processing.progress[id]))
        case .saving: return .running(.savingTranscript)
        case .failed: return job.failure.map { .failed(TranscriptionIssue($0)) }
        case .completed, .cancelled: return nil
        }
    }

    /// The transcript exists, but its files could not be written beside the media.
    var transcriptExportWarning: String? {
        guard !isPreviewing, let id = recordingID else {
            return nil
        }
        return processing?.job(for: id)?.exportFailureDetail
    }

    /// What the app's menus offer for the open recording's transcript now, if anything can be started.
    var transcriptionActionTitle: String? {
        guard !isPreviewing, processing != nil, let recording, !recording.item.isMissing else {
            return nil
        }
        switch transcriptActivity {
        case .queued, .running, .stopping:
            return nil
        case .failed:
            return String(localized: "Retry Transcription")
        case nil:
            return storedTranscript == nil
                ? String(localized: "Generate Transcript") : String(localized: "Re-transcribe")
        }
    }

    /// The transcript is stored, but the recording turned out to hold no speech.
    var hasEmptyTranscript: Bool {
        !isPreviewing && storedTranscript?.segments.isEmpty == true
    }

    /// Jumps to a transcript line, as clicking it does.
    func seekToLine(at index: Int) {
        guard lines.indices.contains(index) else {
            return
        }
        seek(to: lines[index].start)
    }

    func cancelProcessing() {
        if let recordingID {
            processing?.cancel(recordingID)
        }
    }

    /// Loads the stored transcript when this session has not read it yet, or when a job has since finished a new one.
    /// Keeps showing what it has if reading fails: playback doesn't depend on this.
    func reloadTranscriptIfNeeded() async {
        guard !isPreviewing, let processing, let id = recordingID else {
            return
        }
        let job = processing.job(for: id)
        let stamp = job?.state == .completed ? job?.updatedAt : loadedTranscriptStamp
        guard !hasReadTranscript || stamp != loadedTranscriptStamp else {
            return
        }
        do {
            let transcript = try await processing.transcript(for: id)
            guard !Task.isCancelled, id == recordingID else {
                return
            }
            hasReadTranscript = true
            loadedTranscriptStamp = stamp
            show(transcript)
        } catch {
            Self.logger.error("Could not read a transcript: \(String(describing: error))")
        }
    }

    /// Back to how a session starts, before anything has been read.
    func forgetTranscript() {
        forgetSummary()
        storedTranscript = nil
        loadedTranscriptStamp = nil
        hasReadTranscript = false
    }

    // MARK: - Getting it out

    /// The transcript as text, one line each, for the clipboard. Works for what is on screen in design scenarios too.
    var transcriptText: String {
        lines.map { "\(RecordingClock.timerText(for: $0.start)) \($0.speaker.label): \($0.text)" }
            .joined(separator: "\n")
    }

    /// What the save panel saves; rendered only while one is open. Rendered from the stored transcript, so it is the
    /// same as the files beside the media.
    var exportDocument: TranscriptFileDocument? {
        guard let exportRequest, let storedTranscript else {
            return nil
        }
        do {
            return TranscriptFileDocument(data: try exportRequest.format.rendered(storedTranscript))
        } catch {
            Self.logger.error("Could not render a transcript: \(String(describing: error))")
            return nil
        }
    }

    var exportFileName: String {
        title.isEmpty ? "Transcript" : title
    }

    /// Only a stored transcript can be exported; design scenarios have none.
    func requestExport(_ format: ViewerExportFormat) {
        if storedTranscript != nil {
            exportRequest = format
        }
    }

    func finishExport(_ result: Result<URL, any Error>) {
        exportRequest = nil
        if case .failure(let error) = result {
            Self.logger.error("Could not export a transcript: \(String(describing: error))")
            actionIssue = LibraryIssue(
                title: String(localized: "The transcript couldn’t be exported"),
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Private

    private func show(_ transcript: Transcript?) {
        storedTranscript = transcript
        guard var updated = recording else {
            return
        }
        updated.transcript = (transcript?.segments ?? []).enumerated().map { index, segment in
            TranscriptLine(
                id: index,
                start: segment.startTime,
                speaker: TranscriptLine.Speaker(segment.source),
                text: segment.text
            )
        }
        updated.transcriptState = transcript == nil ? .notProcessed : .ready
        updated.language = transcript?.language.flatMap { TranscriptionLanguage.displayName(forCode: $0) } ?? ""
        recording = updated
    }
}
