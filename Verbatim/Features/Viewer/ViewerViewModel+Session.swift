import Foundation

/// Opening and closing real recordings, and the file actions on them. A session is one recording from `open` until the
/// next `open`, `windowClosed()` or a failure, and holds the media access and the player's item for that long.
extension ViewerViewModel {
    /// Replaces whatever is open: the previous playback, its observers and metadata are gone before this returns.
    /// `timestamp` is where to start, in seconds, as a transcript match would ask for.
    func open(recordingID id: UUID, at timestamp: TimeInterval? = nil) {
        guard let library, let playback else {
            return
        }
        endLiveSession()
        isPreviewing = false
        recordingID = id
        recording = nil
        title = ""
        actionIssue = nil
        position = 0
        speed = .normal
        forgetTranscript()
        resetTranscriptPresentation()
        playbackState = .loading
        loadTask = Task { [weak self] in
            await self?.load(id, at: timestamp, library: library, playback: playback)
        }
    }

    /// Reopens after a failure, from the position it had reached.
    func retry() {
        guard let recordingID else {
            return
        }
        open(recordingID: recordingID, at: position)
    }

    /// A closed window plays nothing and keeps nothing open. Design scenarios just stop their clock.
    func windowClosed() {
        guard !isPreviewing else {
            if isPlaying {
                playbackState = .paused
            }
            return
        }
        endLiveSession()
        forgetTranscript()
        recordingID = nil
        recording = nil
        title = ""
        position = 0
        actionIssue = nil
        playbackState = .idle
    }

    /// Follows changes made elsewhere: a new title or files, or the recording leaving the Library, which ends playback.
    func refreshMetadata() async {
        guard !isPreviewing, let library, let id = recordingID, recording != nil else {
            return
        }
        do {
            let stored = try await library.recording(withID: id)
            let inspection = await library.inspect([stored])[id]
            let folder = await library.recordingsFolder().url
            guard !Task.isCancelled, id == recordingID else {
                return
            }
            showMetadata(of: stored, inspection: inspection, recordingsFolder: folder)
            await reloadTranscriptIfNeeded()
        } catch LibraryError.recordingNotFound {
            guard !Task.isCancelled, id == recordingID else {
                return
            }
            recording = nil
            title = ""
            fail(with: .recordingNotFound)
        } catch {
            // Playback does not depend on this; what was last known stays on screen.
            Self.logger.error("Could not refresh a recording's details: \(String(describing: error))")
        }
    }

    // MARK: - File actions

    func showInFinder() {
        performFileAction { try await $0.reveal($1) }
    }

    func openFolder() {
        performFileAction { try await $0.openFolder(of: $1) }
    }

    func showTranscriptInFinder() {
        performFileAction { try await $0.revealTranscript(of: $1) }
    }

    func perform(_ recovery: ViewerIssue.Recovery) {
        switch recovery {
        case .retry: retry()
        case .locateFile: isLocatingFile = true
        case .showInFinder: showInFinder()
        }
    }

    /// Takes the open panel's answer: repoints the Library entry at the chosen file, then plays it.
    func finishLocating(_ result: Result<URL, any Error>) {
        isLocatingFile = false
        switch result {
        case .success(let url):
            performFileAction { [weak self] library, id in
                try await library.relocate(id, to: url)
                self?.open(recordingID: id)
            }
        case .failure(let error):
            Self.logger.error("Choosing a recording's file failed: \(String(describing: error))")
            actionIssue = LibraryIssue(error)
        }
    }

    /// Stores an edited title. A title the Library refuses goes back to what it was.
    func commitTitle() {
        guard !isPreviewing, let current = recording?.item.title, title != current else {
            return
        }
        let newTitle = title
        performFileAction { [weak self] library, id in
            do {
                try await library.rename(id, to: newTitle)
            } catch {
                self?.title = current
                throw error
            }
        }
    }

    func dismissActionIssue() {
        actionIssue = nil
    }

    /// Waits for the work underway, for callers that need its outcome.
    func waitUntilSettled() async {
        await loadTask?.value
        await seekTask?.value
        await actionTask?.value
    }

    // MARK: - Session

    /// Cancels the session's work and releases what it holds. Safe to call with nothing open.
    func endLiveSession() {
        loadTask?.cancel()
        loadTask = nil
        seekTask?.cancel()
        seekTask = nil
        pendingSeek = nil
        isScrubbing = false
        resumesAfterSeek = false
        playback?.unload()
        openMedia?.close()
        openMedia = nil
        mediaInfo = nil
    }

    func fail(with failure: PlaybackFailure) {
        endLiveSession()
        transition(to: .failed(failure))
    }

    func transition(to next: PlaybackState) {
        guard next != playbackState else {
            return
        }
        guard playbackState.allowsTransition(to: next) else {
            let current = String(describing: playbackState)
            Self.logger.error("Ignored a playback change from \(current) to \(String(describing: next))")
            return
        }
        playbackState = next
    }

    // MARK: - Private

    /// The metadata shows first, so a recording whose file cannot play is still identified. A newer `open` or a closed
    /// window cancels this task after releasing the session, so a cancelled load must leave all state alone.
    private func load(
        _ id: UUID,
        at timestamp: TimeInterval?,
        library: LibraryService,
        playback: any PlaybackService
    ) async {
        do {
            let stored = try await library.recording(withID: id)
            let inspection = await library.inspect([stored])[id]
            let folder = await library.recordingsFolder().url
            guard !Task.isCancelled else {
                return
            }
            showMetadata(of: stored, inspection: inspection, recordingsFolder: folder)
            await reloadTranscriptIfNeeded()
            guard !Task.isCancelled else {
                return
            }

            let media = try await library.openMedia(of: id)
            guard !Task.isCancelled else {
                media.close()
                return
            }
            openMedia = media
            let info = try await playback.load(media.url) { [weak self] event in
                self?.handle(event)
            }
            guard !Task.isCancelled else {
                return
            }
            finishLoading(info, stored: stored, at: timestamp)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else {
                return
            }
            Self.logger.error("Could not open a recording: \(String(describing: error))")
            fail(with: PlaybackFailure(error))
        }
    }

    /// Controls run on the media's real length. The stored value stays as it is: it was validated when the recording
    /// was saved or located, and a disagreement is only worth noting for diagnosis.
    private func finishLoading(_ info: PlaybackMediaInfo, stored: LibraryRecording, at timestamp: TimeInterval?) {
        if PlaybackTimeline.durationsDisagree(media: info.duration, stored: stored.recording.duration) {
            Self.logger.notice(
                "Media lasts \(info.duration) s, the Library says \(stored.recording.duration) s; using the media's."
            )
        }
        mediaInfo = info
        playback?.setRate(speed.rawValue)
        playback?.setVolume(volume)
        playback?.setMuted(isMuted)
        transition(to: .ready)
        if let timestamp, timestamp > 0 {
            seek(to: timestamp)
        }
    }

    /// A title being edited is left alone until it is committed.
    private func showMetadata(
        of stored: LibraryRecording,
        inspection: RecordingFileInspection?,
        recordingsFolder: URL
    ) {
        let item = LibraryItem(stored, inspection: inspection, recordingsFolder: recordingsFolder)
        if recording == nil || title == recording?.item.title {
            title = item.title
        }
        recording = ViewerRecording(
            item: item,
            transcript: recording?.transcript ?? [],
            transcriptState: recording?.transcriptState ?? (processing == nil ? .unavailable : .notProcessed),
            language: recording?.language ?? ""
        )
    }

    private func performFileAction(_ action: @escaping @MainActor (LibraryService, UUID) async throws -> Void) {
        guard !isPreviewing, let library, let id = recordingID else {
            return
        }
        actionTask = Task { [weak self] in
            do {
                try await action(library, id)
            } catch {
                Self.logger.error("A Viewer action failed: \(String(describing: error))")
                self?.actionIssue = LibraryIssue(error)
            }
        }
    }
}
