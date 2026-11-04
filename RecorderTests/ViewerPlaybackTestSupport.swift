import Foundation
import Testing

@testable import Recorder

/// A player under the test's control. Loads and seeks can be held open to observe what happens meanwhile.
@MainActor
final class FakePlaybackService: PlaybackService {
    enum Call: Equatable {
        case load(URL)
        case play
        case pause
        case seek(TimeInterval, PlaybackSeekPrecision)
        case rate(Double)
        case volume(Double)
        case muted(Bool)
        case unload
    }

    var currentTime: TimeInterval = 0
    var info = PlaybackMediaInfo(duration: 60, hasVideo: true, audioTrackCount: 2)
    var loadFailure: PlaybackFailure?
    var seekFailure: PlaybackFailure?
    var holdsLoads = false
    var holdsSeeks = false
    private(set) var calls: [Call] = []
    private(set) var onEvent: (@MainActor (PlaybackEvent) -> Void)?
    private var heldLoads: [CheckedContinuation<Void, Never>] = []
    private var heldSeeks: [CheckedContinuation<Void, Never>] = []
    private var generation = 0

    var seeks: [Call] {
        calls.filter {
            if case .seek = $0 {
                return true
            }
            return false
        }
    }

    var hasHeldLoad: Bool { !heldLoads.isEmpty }
    var hasHeldSeek: Bool { !heldSeeks.isEmpty }

    func load(_ url: URL, onEvent: @escaping @MainActor (PlaybackEvent) -> Void) async throws -> PlaybackMediaInfo {
        generation += 1
        let loadGeneration = generation
        calls.append(.load(url))
        if holdsLoads {
            await withCheckedContinuation { heldLoads.append($0) }
        }
        guard loadGeneration == generation else {
            throw CancellationError()
        }
        if let loadFailure {
            throw loadFailure
        }
        self.onEvent = onEvent
        return info
    }

    func play() { calls.append(.play) }
    func pause() { calls.append(.pause) }
    func setRate(_ rate: Double) { calls.append(.rate(rate)) }
    func setVolume(_ volume: Double) { calls.append(.volume(volume)) }
    func setMuted(_ isMuted: Bool) { calls.append(.muted(isMuted)) }

    func seek(to seconds: TimeInterval, precision: PlaybackSeekPrecision) async throws {
        calls.append(.seek(seconds, precision))
        if holdsSeeks {
            await withCheckedContinuation { heldSeeks.append($0) }
        }
        if let seekFailure {
            throw seekFailure
        }
        currentTime = seconds
    }

    func unload() {
        generation += 1
        calls.append(.unload)
        onEvent = nil
        releaseLoads()
        releaseSeeks()
    }

    func releaseLoads() {
        heldLoads.forEach { $0.resume() }
        heldLoads = []
    }

    func releaseSeeks() {
        heldSeeks.forEach { $0.resume() }
        heldSeeks = []
    }

    func emit(_ event: PlaybackEvent) {
        onEvent?(event)
    }
}

@MainActor
protocol ViewerPlaybackTesting {
    var environment: LibraryTestEnvironment { get }
    var repository: SQLiteRecordingRepository { get }
    var library: LibraryService { get }
    var playback: FakePlaybackService { get }
    var viewModel: ViewerViewModel { get }
}

extension ViewerPlaybackTesting {
    func stored(
        _ title: String = "Demo",
        duration: TimeInterval = 60,
        mode: CaptureMode = .screen
    ) async throws -> LibraryRecording {
        let recording = try environment.makeRecording(title: title, duration: duration, mode: mode)
        try await repository.insert(recording)
        return recording
    }

    @discardableResult
    func opened(_ title: String = "Demo") async throws -> LibraryRecording {
        let recording = try await stored(title)
        viewModel.open(recordingID: recording.id)
        await viewModel.waitUntilSettled()
        return recording
    }

    /// Lets the seek loop reach the player, which it does on its own task.
    func waitForHeldSeek() async {
        while !playback.hasHeldSeek {
            await Task.yield()
        }
    }

    func waitForHeldLoad() async {
        while !playback.hasHeldLoad {
            await Task.yield()
        }
    }
}

/// Counts how often opened media is released.
actor CloseCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

struct CountingFileStore: RecordingFileStore {
    let base: LocalRecordingFileStore
    let closes: CloseCounter

    func openMedia(of recording: LibraryRecording) async throws -> OpenMediaFile {
        let media = try await base.openMedia(of: recording)
        let closes = closes
        return OpenMediaFile(url: media.url) {
            media.close()
            Task { await closes.increment() }
        }
    }

    func describeMedia(at url: URL) async throws -> MediaSnapshot { try await base.describeMedia(at: url) }
    func inspect(_ recording: LibraryRecording) async -> RecordingFileInspection { await base.inspect(recording) }
    func validateReplacement(at url: URL, for recording: LibraryRecording) async throws -> MediaSnapshot {
        try await base.validateReplacement(at: url, for: recording)
    }
    func reveal(_ recording: LibraryRecording) async throws { try await base.reveal(recording) }
    func revealFile(named fileName: String, besideMediaOf recording: LibraryRecording) async throws {
        try await base.revealFile(named: fileName, besideMediaOf: recording)
    }
    func openFolder(of recording: LibraryRecording) async throws { try await base.openFolder(of: recording) }
    func openFolder(at url: URL) async throws { try await base.openFolder(at: url) }
    func moveToTrash(_ recording: LibraryRecording) async throws -> [String] {
        try await base.moveToTrash(recording)
    }
}
