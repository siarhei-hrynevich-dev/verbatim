import Foundation

@testable import Verbatim

/// Capture that does nothing except record what was asked of it. `finalizeGate` holds finalization open so tests
/// can observe the state in between.
actor FakeCaptureSession: CaptureSession {
    nonisolated let events: AsyncStream<CaptureEvent>
    nonisolated let eventsContinuation: AsyncStream<CaptureEvent>.Continuation

    private let finalizeResult: Result<CapturedMedia, any Error>
    private var finalizeGate: CheckedContinuation<Void, Never>?
    private var holdsFinalization: Bool
    private(set) var stopCount = 0
    private(set) var finalizeCount = 0
    private(set) var pauseCalls: [Bool] = []

    init(finalizeResult: Result<CapturedMedia, any Error>, holdsFinalization: Bool = false) {
        (events, eventsContinuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        self.finalizeResult = finalizeResult
        self.holdsFinalization = holdsFinalization
    }

    func pause() { pauseCalls.append(true) }
    func resume() { pauseCalls.append(false) }
    func stopCapture() { stopCount += 1 }

    func finalize() async throws -> CapturedMedia {
        finalizeCount += 1
        if holdsFinalization {
            await withCheckedContinuation { finalizeGate = $0 }
        }
        return try finalizeResult.get()
    }

    func releaseFinalization() {
        holdsFinalization = false
        finalizeGate?.resume()
        finalizeGate = nil
    }
}

/// A controllable stand-in for capture, permissions, the recordings folder and metadata storage.
actor FakeRecordingServices: CaptureEngine, RecordingDestinationStore, RecordingMetadataStore {
    var startResult: Result<FakeCaptureSession, any Error>
    var saveError: (any Error)?
    var libraryError: (any Error)?
    var availableBytes: Int64 = 100_000_000_000
    var prepareError: (any Error)?
    var isFolderEmpty = true
    private(set) var startCount = 0
    private(set) var savedMetadata: [RecordingMetadata] = []
    private(set) var libraryEntries: [RecordingMetadata] = []
    private(set) var discardedDestinations: [RecordingDestination] = []
    private(set) var startedConfigurations: [RecordingConfiguration] = []

    init(session: FakeCaptureSession) {
        startResult = .success(session)
    }

    func configure(
        startResult: Result<FakeCaptureSession, any Error>? = nil,
        saveError: (any Error)? = nil,
        libraryError: (any Error)? = nil,
        availableBytes: Int64? = nil,
        prepareError: (any Error)? = nil,
        isFolderEmpty: Bool? = nil
    ) {
        if let startResult {
            self.startResult = startResult
        }
        self.saveError = saveError
        self.libraryError = libraryError
        self.prepareError = prepareError
        self.availableBytes = availableBytes ?? self.availableBytes
        self.isFolderEmpty = isFolderEmpty ?? self.isFolderEmpty
    }

    func startSession(configuration: RecordingConfiguration, outputURL: URL) async throws -> any CaptureSession {
        startCount += 1
        startedConfigurations.append(configuration)
        return try startResult.get()
    }

    func startLevelPreview(microphone: Microphone?, capturesSystemAudio: Bool) async throws -> any CaptureSession {
        FakeCaptureSession(finalizeResult: .failure(RecordingFailure.noMediaCaptured))
    }

    func currentLocation() -> RecordingLocation {
        RecordingLocation(
            url: URL(fileURLWithPath: "/tmp/Verbatim", isDirectory: true),
            displayPath: "~/Movies/Verbatim",
            availableBytes: availableBytes,
            isAccessible: true
        )
    }

    func prepareDestination(id: UUID, createdAt: Date) throws -> RecordingDestination {
        if let prepareError {
            throw prepareError
        }
        let directory = URL(fileURLWithPath: "/tmp/Verbatim/\(id.uuidString)", isDirectory: true)
        return RecordingDestination(directoryURL: directory, mediaURL: directory.appending(path: "recording.mov"))
    }

    func discardIfEmpty(_ destination: RecordingDestination) -> Bool {
        discardedDestinations.append(destination)
        return isFolderEmpty
    }

    func useFolder(_ url: URL) {}
    func useDefaultFolder() {}

    func save(_ metadata: RecordingMetadata, in destination: RecordingDestination) throws {
        if let saveError {
            throw saveError
        }
        savedMetadata.append(metadata)
    }

}

extension FakeRecordingServices: FinishedRecordingRegistry {
    func addFinishedRecording(_ metadata: RecordingMetadata, destination: RecordingDestination) throws {
        if let libraryError {
            throw libraryError
        }
        libraryEntries.append(metadata)
    }
}

/// Permissions fixed for one test. Requests answer with what the access would become.
struct FakePermissions: CapturePermissions {
    var screenCaptureGranted = true
    var microphone = MicrophoneAccess.granted
    var microphoneRequestResult = true

    func hasScreenCaptureAccess() -> Bool { screenCaptureGranted }
    func requestScreenCaptureAccess() async -> Bool { screenCaptureGranted }
    func microphoneAccess() -> MicrophoneAccess { microphone }
    func requestMicrophoneAccess() async -> Bool { microphoneRequestResult }
}

struct FakeSourceProvider: CaptureSourceProviding {
    var sources = CaptureSources()
    var microphones: [Microphone] = []

    func availableSources() async throws -> CaptureSources { sources }
    func availableMicrophones() async -> [Microphone] { microphones }
    func windowThumbnails(for windowIDs: [CaptureWindow.ID]) async -> [CaptureWindow.ID: Data] { [:] }
}

final class InMemoryPreferencesStore: RecordingPreferencesStore, @unchecked Sendable {
    // Tests use this from the main actor only.
    var preferences: RecordingPreferences

    init(_ preferences: RecordingPreferences = RecordingPreferences()) {
        self.preferences = preferences
    }

    func load() -> RecordingPreferences { preferences }
    func save(_ preferences: RecordingPreferences) { self.preferences = preferences }
}

struct NoSystemActions: SystemActions {
    func open(_ pane: SystemSettingsPane) async {}
    func openInFinder(_ url: URL) async {}
    func revealInFinder(_ url: URL) async {}
    func openFile(_ url: URL) async -> Bool { true }
}

enum TestError: Error {
    case failed
}

enum TestFixtures {
    static let display = CaptureDisplay(id: "display-1", name: "Studio Display", pixelWidth: 5120, pixelHeight: 2880)
    static let window = CaptureWindow(id: "42", appName: "Notes", title: "Agenda", bundleIdentifier: "com.apple.Notes")
    static let microphone = Microphone(id: "mic-1", name: "USB Microphone")
    static let media = CapturedMedia(
        duration: 12,
        fileSizeBytes: 4_096,
        hasVideo: true,
        audioSources: [.microphone, .systemAudio]
    )

    static func configuration(
        target: CaptureTarget? = .display(display),
        microphone: Microphone? = microphone,
        capturesSystemAudio: Bool = true,
        transcribes: Bool = true
    ) -> RecordingConfiguration {
        RecordingConfiguration(
            target: target,
            microphone: microphone,
            capturesSystemAudio: capturesSystemAudio,
            quality: .hd1080,
            frameRate: .fps60,
            transcribesWhenFinished: transcribes
        )
    }
}
