import AVFoundation
import os

/// `PlaybackService` on one reused `AVPlayer`, created at first use. AVFoundation reads the file as needed, so the
/// media is never loaded into memory. Only one item exists at a time, which rules out overlapping audio.
///
/// Observers are registered on the main queue, which is why their callbacks can assume main-actor isolation.
@MainActor
final class AVPlaybackService: PlaybackService {
    private var createdPlayer: AVPlayer?
    private var currentItem: AVPlayerItem?
    private var onEvent: (@MainActor (PlaybackEvent) -> Void)?
    private var timeObserver: Any?
    private var notificationObservers: [any NSObjectProtocol] = []
    private var statusTask: Task<Void, Never>?
    /// Advances on every `load` and `unload()`, so a load that was overtaken while suspended can tell.
    private var generation = 0

    /// The player, for the view that renders its video.
    var player: AVPlayer {
        if let createdPlayer {
            return createdPlayer
        }
        let player = AVPlayer()
        // Files are local, so there is nothing to wait for; waiting would only delay the start.
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .pause
        createdPlayer = player
        return player
    }

    var currentTime: TimeInterval {
        guard let seconds = createdPlayer?.currentTime().seconds, seconds.isFinite else {
            return 0
        }
        return seconds
    }

    // MARK: - Loading

    func load(_ url: URL, onEvent: @escaping @MainActor (PlaybackEvent) -> Void) async throws -> PlaybackMediaInfo {
        unload()
        let loadGeneration = generation
        let asset = AVURLAsset(url: url)
        let info = try await describe(asset)
        try requireCurrent(loadGeneration)

        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        currentItem = item
        try await waitUntilReady(item)
        try requireCurrent(loadGeneration)

        self.onEvent = onEvent
        observe(item)
        return info
    }

    func unload() {
        generation += 1
        statusTask?.cancel()
        statusTask = nil
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers = []
        if let timeObserver {
            createdPlayer?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        onEvent = nil
        createdPlayer?.pause()
        createdPlayer?.replaceCurrentItem(with: nil)
        currentItem = nil
    }

    // MARK: - Transport

    func play() {
        player.play()
    }

    func pause() {
        createdPlayer?.pause()
    }

    func seek(to seconds: TimeInterval, precision: PlaybackSeekPrecision) async throws {
        guard let item = currentItem, item.status == .readyToPlay, seconds.isFinite else {
            throw PlaybackFailure.seekFailed
        }
        let tolerance =
            switch precision {
            case .exact: CMTime.zero
            case .approximate: CMTime(seconds: Self.scrubToleranceSeconds, preferredTimescale: Self.timescale)
            }
        // A `false` result means a newer seek or an unload interrupted this one, which the contract does not treat as
        // a failure. A failed item is the detectable problem.
        _ = await player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: Self.timescale),
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        )
        guard item.status != .failed else {
            throw PlaybackFailure.seekFailed
        }
    }

    func setRate(_ rate: Double) {
        player.defaultRate = Float(rate)
        if player.rate != 0 {
            player.rate = Float(rate)
        }
    }

    func setVolume(_ volume: Double) {
        player.volume = Float(volume)
    }

    func setMuted(_ isMuted: Bool) {
        player.isMuted = isMuted
    }

    // MARK: - Private

    private func requireCurrent(_ loadGeneration: Int) throws {
        guard loadGeneration == generation, !Task.isCancelled else {
            throw CancellationError()
        }
    }

    private func describe(_ asset: AVURLAsset) async throws -> PlaybackMediaInfo {
        let isPlayable: Bool
        let duration: CMTime
        let tracks: [AVAssetTrack]
        do {
            (isPlayable, duration, tracks) = try await asset.load(.isPlayable, .duration, .tracks)
        } catch {
            try Task.checkCancellation()
            Self.logger.error("Could not read media: \(String(describing: error))")
            throw PlaybackFailure(mediaError: error)
        }
        let videoTracks = tracks.count { $0.mediaType == .video }
        let audioTracks = tracks.count { $0.mediaType == .audio }
        guard videoTracks + audioTracks > 0, duration.isNumeric, duration.seconds > 0 else {
            throw PlaybackFailure.corruptedMedia
        }
        guard isPlayable else {
            throw PlaybackFailure.unsupportedFormat
        }
        return PlaybackMediaInfo(
            duration: duration.seconds,
            hasVideo: videoTracks > 0,
            audioTrackCount: audioTracks
        )
    }

    private func waitUntilReady(_ item: AVPlayerItem) async throws {
        for await status in Self.statusUpdates(of: item) {
            switch status {
            case .readyToPlay:
                return
            case .failed:
                let error = item.error
                Self.logger.error("Could not start playback: \(String(describing: error))")
                throw error.map(PlaybackFailure.init(mediaError:)) ?? .loadFailed(detail: "Unknown player error")
            case .unknown:
                continue
            @unknown default:
                continue
            }
        }
        throw CancellationError()
    }

    private func observe(_ item: AVPlayerItem) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: Self.timeUpdateIntervalSeconds, preferredTimescale: Self.timescale),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            MainActor.assumeIsolated {
                if seconds.isFinite {
                    self?.onEvent?(.timeChanged(seconds))
                }
            }
        }
        let center = NotificationCenter.default
        let endObserver = center.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.playedToEnd) }
        }
        let failureObserver = center.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            let detail = error.map(String.init(describing:)) ?? "Unknown player error"
            MainActor.assumeIsolated { self?.reportFailure(.playbackFailed(detail: detail)) }
        }
        let rateObserver = center.addObserver(
            forName: AVPlayer.rateDidChangeNotification,
            object: player,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportIfStopped() }
        }
        notificationObservers = [endObserver, failureObserver, rateObserver]
        statusTask = Task { [weak self, item] in
            for await status in Self.statusUpdates(of: item) where status == .failed {
                let failure = item.error.map(PlaybackFailure.init(mediaError:))
                self?.reportFailure(failure ?? .playbackFailed(detail: "Unknown player error"))
                return
            }
        }
    }

    /// The item's status as it changes, starting with the current one. Combine's `publisher(for:).values` will not do:
    /// it drops a change that arrives between two iterations, and waiting for the next one would then never end.
    /// Nonisolated because KVO calls back on whichever thread made the change.
    private nonisolated static func statusUpdates(of item: AVPlayerItem) -> AsyncStream<AVPlayerItem.Status> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observation = item.observe(\.status, options: [.initial, .new]) { item, _ in
                continuation.yield(item.status)
            }
            continuation.onTermination = { _ in observation.invalidate() }
        }
    }

    /// The rate is read when the notification arrives, so a pause followed right away by play reports nothing.
    private func reportIfStopped() {
        if createdPlayer?.rate == 0 {
            onEvent?(.paused)
        }
    }

    private func reportFailure(_ failure: PlaybackFailure) {
        Self.logger.error("Playback failed: \(String(describing: failure))")
        onEvent?(.failed(failure))
    }

    private static let timescale: CMTimeScale = 90_000
    /// Often enough for the position bar of a short recording to move smoothly, without waking the UI per frame.
    private static let timeUpdateIntervalSeconds: TimeInterval = 0.1
    private static let scrubToleranceSeconds: TimeInterval = 0.5
    private static let logger = Logger(category: "Playback")
}

extension PlaybackFailure {
    /// Translates errors from AVFoundation, which often carry the actual cause as an underlying error.
    init(mediaError error: any Error) {
        var current: NSError? = error as NSError
        while let nsError = current {
            if let failure = Self.failure(for: nsError) {
                self = failure
                return
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        self = .loadFailed(detail: String(describing: error))
    }

    private static func failure(for error: NSError) -> PlaybackFailure? {
        if error.domain == AVFoundationErrorDomain {
            return failure(forAVErrorCode: error.code)
        }
        if accessDeniedCodes[error.domain]?.contains(error.code) == true {
            return .mediaUnavailable(.accessDenied)
        }
        if missingFileCodes[error.domain]?.contains(error.code) == true {
            return .mediaUnavailable(.missing)
        }
        return nil
    }

    private static let accessDeniedCodes: [String: Set<Int>] = [
        NSCocoaErrorDomain: [NSFileReadNoPermissionError],
        NSURLErrorDomain: [NSURLErrorNoPermissionsToReadFile],
        NSPOSIXErrorDomain: [Int(EACCES), Int(EPERM)]
    ]

    private static let missingFileCodes: [String: Set<Int>] = [
        NSCocoaErrorDomain: [NSFileReadNoSuchFileError, NSFileNoSuchFileError],
        NSURLErrorDomain: [NSURLErrorFileDoesNotExist],
        NSPOSIXErrorDomain: [Int(ENOENT)]
    ]

    private static func failure(forAVErrorCode code: Int) -> PlaybackFailure? {
        switch AVError.Code(rawValue: code) {
        case .fileFormatNotRecognized, .decoderNotFound, .formatUnsupported, .fileTypeDoesNotSupportSampleReferences:
            .unsupportedFormat
        case .fileFailedToParse, .failedToParse, .noLongerPlayable, .decodeFailed, .mediaDiscontinuity:
            .corruptedMedia
        default:
            nil
        }
    }
}
