import Foundation

/// Plays one local media file at a time, for video and audio-only recordings alike.
///
/// Main-actor isolated because the player it wraps drives on-screen rendering. Knows nothing about recordings or
/// transcripts: anything that follows the timeline, such as a transcript, uses `PlaybackEvent.timeChanged`,
/// `currentTime` and `seek(to:precision:)`.
@MainActor
protocol PlaybackService: AnyObject {
    /// The playhead in seconds from the start of the media; 0 when nothing is loaded.
    var currentTime: TimeInterval { get }

    /// Replaces whatever is loaded and starts paused at the beginning, without reading the file into memory. `onEvent`
    /// is called on the main actor until `unload()` or the next `load`. Throws `PlaybackFailure`, or
    /// `CancellationError` if the task is cancelled or another `load` or `unload()` takes over.
    func load(_ url: URL, onEvent: @escaping @MainActor (PlaybackEvent) -> Void) async throws -> PlaybackMediaInfo
    func play()
    func pause()
    /// Returns when the player has landed, or when a newer seek or `unload()` has taken over, which is not a failure.
    /// Throws `PlaybackFailure.seekFailed` when the media can no longer seek.
    func seek(to seconds: TimeInterval, precision: PlaybackSeekPrecision) async throws
    /// 1 is normal speed. Applies now if playing, otherwise from the next `play()`.
    func setRate(_ rate: Double)
    /// From 0 to 1.
    func setVolume(_ volume: Double)
    func setMuted(_ isMuted: Bool)
    /// Stops playback, removes observers and releases the media. Safe to call with nothing loaded.
    func unload()
}
