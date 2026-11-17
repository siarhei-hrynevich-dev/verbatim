import Foundation

/// Transport controls and the timeline. Seeks go through one loop at a time and only the newest target matters, so
/// dragging across a long recording never queues up work. While a drag or a seek is underway, the player's own time
/// reports are ignored, which is what keeps the thumb from jumping back.
extension ViewerViewModel {
    func togglePlayback() {
        if isPreviewing {
            toggleSimulatedPlayback()
            return
        }
        switch playbackState {
        case .ended:
            replay()
        case .ready, .paused:
            togglePausedPlayback()
        case .playing:
            pause()
        case .idle, .loading, .failed:
            break
        }
    }

    func pause() {
        resumesAfterSeek = false
        guard isPlaying else {
            return
        }
        playback?.pause()
        transition(to: .paused)
    }

    func skip(by seconds: TimeInterval) {
        seek(to: position + seconds)
    }

    /// Moves the playhead. Out-of-range positions land on the nearest end, and non-numbers are refused.
    func seek(to newPosition: TimeInterval) {
        guard let target = PlaybackTimeline.validatedPosition(newPosition, duration: duration) else {
            return
        }
        if isPreviewing {
            position = target
            return
        }
        guard canControlPlayback else {
            return
        }
        enqueueSeek(to: target, precision: .exact)
    }

    // MARK: - Scrubbing

    /// Starts a drag on the timeline. Playback holds while dragging and continues after, as it does in QuickTime.
    func beginScrubbing() {
        guard !isPreviewing, canControlPlayback, !isScrubbing else {
            return
        }
        isScrubbing = true
        if isPlaying {
            playback?.pause()
            transition(to: .paused)
            resumesAfterSeek = true
        }
    }

    /// Follows the drag with quick seeks to nearby frames.
    func scrub(to newPosition: TimeInterval) {
        guard let target = PlaybackTimeline.validatedPosition(newPosition, duration: duration) else {
            return
        }
        if isPreviewing {
            position = target
            return
        }
        if isScrubbing {
            enqueueSeek(to: target, precision: .approximate)
        }
    }

    /// Ends the drag with a seek to exactly where it stopped.
    func endScrubbing(at newPosition: TimeInterval) {
        if isPreviewing {
            scrub(to: newPosition)
            return
        }
        guard isScrubbing else {
            return
        }
        isScrubbing = false
        let target = PlaybackTimeline.validatedPosition(newPosition, duration: duration) ?? position
        enqueueSeek(to: target, precision: .exact)
    }

    // MARK: - Speed and volume

    func cycleSpeed() {
        speed = speed.next
        playback?.setRate(speed.rawValue)
    }

    /// Raising the volume while muted unmutes, as the system's volume does.
    func setVolume(_ newVolume: Double) {
        guard newVolume.isFinite else {
            return
        }
        volume = min(max(newVolume, 0), 1)
        playback?.setVolume(volume)
        if isMuted, volume > 0 {
            toggleMute()
        }
    }

    func toggleMute() {
        isMuted.toggle()
        playback?.setMuted(isMuted)
    }

    // MARK: - Playback events

    /// Everything the player reports on its own. Reports cannot come from an earlier recording: the service stops
    /// calling this at `unload()`, which every session change goes through.
    func handle(_ event: PlaybackEvent) {
        let isMovingPlayhead = isScrubbing || seekTask != nil
        switch event {
        case .timeChanged(let seconds):
            guard !isMovingPlayhead, playbackState.isLoaded, playbackState != .ended,
                let reported = PlaybackTimeline.validatedPosition(seconds, duration: duration), reported != position
            else {
                return
            }
            position = reported
        case .paused:
            if isPlaying, !isMovingPlayhead {
                transition(to: .paused)
            }
        case .playedToEnd:
            // After a seek, `settleAfterSeeks` decides from where the playhead landed.
            if !isMovingPlayhead {
                finishAtEnd()
            }
        case .failed(let failure):
            fail(with: failure)
        }
    }

    // MARK: - Private

    private func togglePausedPlayback() {
        if resumesAfterSeek {
            resumesAfterSeek = false
        } else if PlaybackTimeline.isAtEnd(position, duration: duration) {
            replay()
        } else {
            startPlaying()
        }
    }

    private func startPlaying() {
        guard seekTask == nil else {
            resumesAfterSeek = true
            return
        }
        playback?.play()
        transition(to: .playing)
    }

    private func replay() {
        resumesAfterSeek = true
        enqueueSeek(to: 0, precision: .exact)
    }

    private func finishAtEnd() {
        resumesAfterSeek = false
        position = duration
        if isPlaying {
            playback?.pause()
        }
        transition(to: .ended)
    }

    /// The playhead shows the target right away. Anywhere but the end, `ready` and `ended` no longer describe it.
    private func enqueueSeek(to target: TimeInterval, precision: PlaybackSeekPrecision) {
        position = target
        if playbackState == .ready || playbackState == .ended {
            transition(to: .paused)
        }
        pendingSeek = PendingSeek(target: target, precision: precision)
        guard seekTask == nil else {
            return
        }
        seekTask = Task { [weak self] in
            await self?.runPendingSeeks()
        }
    }

    /// A cancelled loop belongs to a session that has ended, and must not touch the next one's seeks.
    private func runPendingSeeks() async {
        while let seek = pendingSeek {
            pendingSeek = nil
            do {
                try await playback?.seek(to: seek.target, precision: seek.precision)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                Self.logger.error("A seek failed: \(String(describing: error))")
                pendingSeek = nil
                resumesAfterSeek = false
                position = playback?.currentTime ?? position
                actionIssue = LibraryIssue(
                    title: String(localized: "Couldn’t move to that position"),
                    message: String(localized: "Playback stays where it was. Try another position.")
                )
            }
            guard !Task.isCancelled else {
                return
            }
        }
        seekTask = nil
        settleAfterSeeks()
    }

    private func settleAfterSeeks() {
        guard !isScrubbing else {
            return
        }
        if PlaybackTimeline.isAtEnd(position, duration: duration) {
            finishAtEnd()
        } else if resumesAfterSeek {
            resumesAfterSeek = false
            startPlaying()
        }
    }

    private func toggleSimulatedPlayback() {
        if isPlaying {
            playbackState = .paused
            return
        }
        if position >= duration {
            position = 0
        }
        playbackState = .playing
    }
}
