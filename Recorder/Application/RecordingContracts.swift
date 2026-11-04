import Foundation

/// Discovers what can be captured. Never triggers a permission prompt.
protocol CaptureSourceProviding: Sendable {
    func availableSources() async throws -> CaptureSources
    func availableMicrophones() async -> [Microphone]
    /// JPEG thumbnails keyed by window identifier. Windows without a thumbnail are simply absent.
    func windowThumbnails(for windowIDs: [CaptureWindow.ID]) async -> [CaptureWindow.ID: Data]
}

/// Something that happened while capture was running.
enum CaptureEvent: Sendable {
    case levels(AudioLevels)
    case videoSourceLost
    case microphoneLost
    case systemAudioLost(detail: String)
    case writeFailed(detail: String)
}

/// Running capture. Capture stops first, then the media is finalized, so a failure in one step is distinguishable.
protocol CaptureSession: AnyObject, Sendable {
    var events: AsyncStream<CaptureEvent> { get }
    func pause() async
    func resume() async
    func stopCapture() async
    /// Closes and validates the media file. Throws `RecordingFailure.noMediaCaptured` if nothing was written.
    func finalize() async throws -> CapturedMedia
}

/// Starts capture. Throws `RecordingFailure` when a source is unavailable or capture cannot begin.
protocol CaptureEngine: Sendable {
    func startSession(configuration: RecordingConfiguration, outputURL: URL) async throws -> any CaptureSession
    /// Runs audio capture only for its level events, writing nothing.
    func startLevelPreview(microphone: Microphone?, capturesSystemAudio: Bool) async throws -> any CaptureSession
}

enum MicrophoneAccess: Sendable {
    case notDetermined
    case granted
    case denied
}

protocol CapturePermissions: Sendable {
    /// Checks without prompting.
    func hasScreenCaptureAccess() -> Bool
    /// Prompts the first time; macOS answers without prompting afterward.
    func requestScreenCaptureAccess() async -> Bool
    func microphoneAccess() -> MicrophoneAccess
    func requestMicrophoneAccess() async -> Bool
}

/// Owns the recordings folder and creates a folder per recording.
protocol RecordingDestinationStore: Sendable {
    func currentLocation() async -> RecordingLocation
    /// Creates a new empty folder for one recording, never reusing an existing one.
    /// Throws `RecordingFailure.destinationUnavailable` when the folder cannot be created.
    func prepareDestination(id: UUID, createdAt: Date) async throws -> RecordingDestination
    /// Removes the folder only if nothing was written to it. Returns whether it was removed.
    func discardIfEmpty(_ destination: RecordingDestination) async -> Bool
    func useFolder(_ url: URL) async throws
    func useDefaultFolder() async
}

/// Writes the sidecar kept beside a recording's media: a snapshot from when it finished, or a note that it did not.
protocol RecordingMetadataStore: Sendable {
    func save(_ metadata: RecordingMetadata, in destination: RecordingDestination) async throws
}

/// Takes in recordings whose media is finalized and validated. Never called for unfinished media.
protocol FinishedRecordingRegistry: Sendable {
    func addFinishedRecording(_ metadata: RecordingMetadata, destination: RecordingDestination) async throws
}

protocol RecordingPreferencesStore: Sendable {
    func load() -> RecordingPreferences
    func save(_ preferences: RecordingPreferences)
}

/// A System Settings page that fixes a problem shown to the user.
enum SystemSettingsPane: Equatable, Sendable {
    case screenRecording
    case microphone
    case storage
    case loginItems
}

/// Hands off to the operating system's own UI.
protocol SystemActions: Sendable {
    func open(_ pane: SystemSettingsPane) async
    func openInFinder(_ url: URL) async
    /// Shows the item selected in its Finder window.
    func revealInFinder(_ url: URL) async
    /// Opens a file or folder in its default application. Returns whether the system accepted the request.
    func openFile(_ url: URL) async -> Bool
}
