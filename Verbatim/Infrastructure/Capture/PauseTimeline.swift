import CoreMedia

/// Maps capture time to output time so that paused intervals leave no gap in the recording. All audio and video
/// sources share the host clock, so one timeline applies to every track.
struct PauseTimeline {
    private var completedPauses: [CMTimeRange] = []
    private var activePauseStart: CMTime?

    mutating func pause(at time: CMTime) {
        guard activePauseStart == nil else {
            return
        }
        activePauseStart = time
    }

    mutating func resume(at time: CMTime) {
        guard let start = activePauseStart else {
            return
        }
        completedPauses.append(CMTimeRange(start: start, end: time))
        activePauseStart = nil
    }

    /// The output time of a sample captured at `time`, or `nil` if it was captured during a pause.
    func outputTime(for time: CMTime) -> CMTime? {
        if let activePauseStart, time >= activePauseStart {
            return nil
        }
        guard !completedPauses.contains(where: { $0.containsTime(time) }) else {
            return nil
        }
        let earlierPauses = completedPauses.filter { $0.end <= time }
        return earlierPauses.reduce(time) { outputTime, pause in outputTime - pause.duration }
    }

    /// The output time at which a recording stopped at `time` ends, which while paused is when the pause began.
    func endTime(forStopAt time: CMTime) -> CMTime? {
        outputTime(for: activePauseStart.map { $0 - CMTime(value: 1, timescale: 1_000_000_000) } ?? time)
    }
}
