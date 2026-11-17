import Foundation

/// What a recording points its video capture at.
enum CaptureTarget: Equatable, Sendable {
    case display(CaptureDisplay)
    case window(CaptureWindow)
    case audioOnly

    var mode: CaptureMode {
        switch self {
        case .display: .screen
        case .window: .window
        case .audioOnly: .audioOnly
        }
    }
}

/// Everything needed to start one recording.
struct RecordingConfiguration: Equatable, Sendable {
    let target: CaptureTarget?
    let microphone: Microphone?
    let capturesSystemAudio: Bool
    let quality: VideoQuality
    let frameRate: FrameRate
    let transcribesWhenFinished: Bool

    var capturesVideo: Bool {
        guard let target else {
            return false
        }
        return target.mode.capturesVideo
    }

    /// Video and system audio both come from ScreenCaptureKit; microphone-only recordings do not need it.
    var requiresScreenCaptureAccess: Bool {
        capturesVideo || capturesSystemAudio
    }

    var requiresMicrophoneAccess: Bool {
        microphone != nil
    }

    var audioSources: [AudioSourceKind] {
        var sources: [AudioSourceKind] = []
        if microphone != nil {
            sources.append(.microphone)
        }
        if capturesSystemAudio {
            sources.append(.systemAudio)
        }
        return sources
    }

    /// The source as named to the user.
    var sourceName: String {
        switch target {
        case .display(let display): display.name
        case .window(let window): "\(window.appName) — \(window.title)"
        case .audioOnly: String(localized: "Audio Only")
        case nil: ""
        }
    }

    /// Throws when the configuration cannot produce any media.
    func validate() throws(RecordingFailure) {
        guard target != nil else {
            throw .noCaptureSourceSelected
        }
        guard capturesVideo || capturesSystemAudio || microphone != nil else {
            throw .noEnabledSource
        }
    }

    /// Rough output rate for disk space warnings. A window's size is unknown until capture, so 1080p stands in.
    var estimatedBytesPerSecond: Int64 {
        var bytesPerSecond = VideoEncodingProfile.audioBytesPerSecond
        if capturesVideo {
            let size = quality.outputSize(forSource: estimatedSourceSize)
            bytesPerSecond += Int64(VideoEncodingProfile.averageBitRate(for: size, frameRate: frameRate) / 8)
        }
        return bytesPerSecond
    }

    private var estimatedSourceSize: PixelSize {
        if case .display(let display) = target {
            return PixelSize(width: display.pixelWidth, height: display.pixelHeight)
        }
        return PixelSize(width: 1920, height: 1080)
    }
}

/// When free space is too low to record, or low enough to warn about.
enum DiskSpacePolicy {
    enum Assessment: Equatable, Sendable {
        case sufficient
        case low(minutesRemaining: Int)
        case insufficient
    }

    /// Below this, a recording could not store more than a few minutes and the volume itself is at risk.
    static let minimumFreeBytes: Int64 = 500_000_000

    private static let warningMinutes = 15

    static func assess(freeBytes: Int64, bytesPerSecond: Int64) -> Assessment {
        guard freeBytes >= minimumFreeBytes else {
            return .insufficient
        }
        let minutes = Int(freeBytes / max(bytesPerSecond, 1) / 60)
        return minutes < warningMinutes ? .low(minutesRemaining: minutes) : .sufficient
    }
}
