import Foundation

/// What a recording captures.
enum CaptureMode: String, CaseIterable, Codable, Sendable {
    case screen
    case window
    case audioOnly

    var capturesVideo: Bool {
        self != .audioOnly
    }
}

enum VideoQuality: String, CaseIterable, Codable, Sendable {
    case hd720 = "720p"
    case hd1080 = "1080p"
    case native = "Native"
}

enum FrameRate: Int, CaseIterable, Codable, Sendable {
    case fps30 = 30
    case fps60 = 60
}

/// A display that can be captured. `id` stays stable across launches and reconnections.
struct CaptureDisplay: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
}

/// An application window that can be captured. `id` is valid only while the window exists, so remembering a
/// window across launches also relies on its bundle identifier and title.
struct CaptureWindow: Identifiable, Hashable, Sendable {
    let id: String
    let appName: String
    let title: String
    var bundleIdentifier = ""
}

/// An audio input device.
struct Microphone: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

/// The displays and windows that can be captured right now.
struct CaptureSources: Equatable, Sendable {
    var displays: [CaptureDisplay] = []
    var windows: [CaptureWindow] = []
}

/// One of the separately stored audio sources of a recording.
enum AudioSourceKind: String, Codable, Sendable {
    case microphone
    case systemAudio
}

/// Live audio levels, each normalized to `0...1`.
struct AudioLevels: Equatable, Sendable {
    static let silent = AudioLevels(microphone: 0, systemAudio: 0)

    var microphone: Double
    var systemAudio: Double

    /// Maps a linear RMS amplitude to `0...1` along the decibel scale, where silence is `silenceFloorDecibels`.
    static func normalized(rms: Double) -> Double {
        guard rms.isFinite, rms > 0 else {
            return 0
        }
        let decibels = 20 * log10(rms)
        return min(max((decibels - silenceFloorDecibels) / -silenceFloorDecibels, 0), 1)
    }

    /// Quieter input than this reads as silence on the meters.
    private static let silenceFloorDecibels = -50.0
}
