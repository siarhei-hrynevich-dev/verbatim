import Foundation

/// Naming of a recording's folder and files. Folder names sort by time, and the identifier rules out collisions.
enum RecordingFileLayout {
    static let metadataFileName = "recording.json"
    /// QuickTime for audio-only recordings too: MPEG-4 audio files lose the track names that keep the microphone
    /// and system audio identifiable.
    static let mediaFileName = "recording.mov"
    /// Plain text first: it is the one a person most likely wants to find.
    static let transcriptFileNames = ["transcript.txt", "transcript.srt", "transcript.json"]
    /// Files the app writes or will write into a recording's folder besides the media.
    static let derivedFileNames = Set(transcriptFileNames + [metadataFileName])

    /// The transcript file among a recording's files, if it has one.
    static func transcriptFileName(in fileNames: [String]) -> String? {
        transcriptFileNames.first(where: fileNames.contains)
    }

    static func directoryName(createdAt: Date, id: UUID, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return "\(formatter.string(from: createdAt))_\(id.uuidString.lowercased())"
    }

    /// Whether a folder is the one the app created for this recording. A folder the user made, or renamed, is theirs:
    /// only files inside it that are known to belong to the recording may be touched.
    static func isOwnedDirectory(named name: String, recordingID: UUID) -> Bool {
        name.hasSuffix("_\(recordingID.uuidString.lowercased())")
    }
}

/// Where one recording's files live.
struct RecordingDestination: Equatable, Sendable {
    let directoryURL: URL
    let mediaURL: URL
}

/// What the finished media file turned out to contain.
struct CapturedMedia: Equatable, Sendable {
    let duration: TimeInterval
    let fileSizeBytes: Int64
    let hasVideo: Bool
    let audioSources: [AudioSourceKind]
}

/// Everything stored about one recording next to its media.
struct RecordingMetadata: Codable, Equatable, Sendable {
    enum Completion: String, Codable, Sendable {
        case complete
        /// Finalization failed; the media may still be recoverable.
        case incomplete
    }

    let recording: Recording
    let mediaFileName: String
    let captureMode: CaptureMode
    let sourceName: String
    let hasVideo: Bool
    let audioSources: [AudioSourceKind]
    let fileSizeBytes: Int64
    let completion: Completion
    /// The Recorder's “Transcribe when recording ends” choice, as it stood for this recording.
    let transcriptionRequested: Bool

    static func defaultTitle(createdAt: Date) -> String {
        let time = createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return String(localized: "Recording \(time)")
    }
}

/// Something that cut a recording short or removed one of its sources.
enum RecordingInterruption: Equatable, Sendable {
    case sourceLost(name: String)
    case microphoneLost(name: String)
    case systemAudioLost(detail: String)
    case writeFailed(detail: String)
}

/// A recording whose media finished and validated. Only ever produced after finalization.
struct RecordingOutcome: Equatable, Sendable {
    let metadata: RecordingMetadata
    let destination: RecordingDestination
    let interruptions: [RecordingInterruption]
    /// Set when the media is safe but its metadata could not be stored.
    let metadataErrorDetail: String?
}

/// The folder recordings go to.
struct RecordingLocation: Equatable, Sendable {
    let url: URL
    /// The folder as shown to the user, such as `~/Movies/Verbatim`.
    let displayPath: String
    let availableBytes: Int64
    let isAccessible: Bool
}

/// The user's recording settings, restored at launch.
struct RecordingPreferences: Equatable, Sendable {
    var captureMode = CaptureMode.screen
    var displayID: String?
    var windowID: String?
    var windowBundleIdentifier: String?
    var windowTitle: String?
    var microphoneID: String?
    var isMicrophoneEnabled = true
    var isSystemAudioEnabled = true
    var quality = VideoQuality.hd1080
    var frameRate = FrameRate.fps60
    var transcribesWhenFinished = true
}
