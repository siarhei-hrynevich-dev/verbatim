import AVFoundation
import Foundation
import Testing

@testable import Recorder

/// The real player on real media from the app's own writer, muted. Needs no permissions or audio hardware.
@MainActor
struct AVPlaybackServiceTests {
    private let environment: LibraryTestEnvironment
    private let service = AVPlaybackService()

    init() throws {
        environment = try LibraryTestEnvironment()
        service.setMuted(true)
    }

    /// Collects what the service reports.
    @MainActor
    private final class EventLog {
        var events: [PlaybackEvent] = []

        var hasEnded: Bool {
            events.contains(.playedToEnd)
        }

        var lastTime: TimeInterval? {
            for event in events.reversed() {
                if case .timeChanged(let seconds) = event {
                    return seconds
                }
            }
            return nil
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func loadsAVideoRecording() async throws {
        let url = try await environment.writePlayableMedia(hasVideo: true)

        let info = try await service.load(url) { _ in }

        #expect(info.hasVideo)
        #expect(info.audioTrackCount == 1)
        #expect(abs(info.duration - 1) < 0.1)
        #expect(service.currentTime == 0)
    }

    @Test func loadsAnAudioOnlyRecording() async throws {
        let url = try await environment.writePlayableMedia(hasVideo: false)

        let info = try await service.load(url) { _ in }

        #expect(!info.hasVideo)
        #expect(info.audioTrackCount == 1)
    }

    @Test func bothAudioSourcesOfARecordingStayEnabled() async throws {
        let url = environment.root.appending(path: "two-tracks.mov")
        let writer = try MediaFileWriter(url: url, video: nil, audioSources: [.microphone, .systemAudio])
        for index in 0..<10 {
            let time = CMTime(seconds: 10 + Double(index) / 10, preferredTimescale: 48_000)
            writer.appendAudio(try SyntheticSamples.audio(at: time, channels: 1, seconds: 0.1), from: .microphone)
            writer.appendAudio(try SyntheticSamples.audio(at: time, channels: 2, seconds: 0.1), from: .systemAudio)
        }
        try await writer.finish(stopTime: CMTime(seconds: 11, preferredTimescale: 48_000))

        let info = try await service.load(url) { _ in }

        #expect(info.audioTrackCount == 2)
        let tracks = try #require(service.player.currentItem?.tracks)
        #expect(tracks.count == 2)
        let enabledCount = tracks.count { $0.isEnabled }
        #expect(enabledCount == 2)
    }

    @Test func playsToTheEndAndReportsIt() async throws {
        let url = try await environment.writePlayableMedia(hasVideo: true)
        let log = EventLog()
        _ = try await service.load(url) { log.events.append($0) }

        service.play()
        try await waitUntil { log.hasEnded }

        #expect(log.hasEnded)
        #expect((log.lastTime ?? 0) > 0)
    }

    @Test func seeksToAnExactTimestamp() async throws {
        let url = try await environment.writePlayableMedia(hasVideo: true)
        _ = try await service.load(url) { _ in }

        try await service.seek(to: 0.5, precision: .exact)

        #expect(abs(service.currentTime - 0.5) < 0.05)
    }

    @Test func theAudioOnlyEngineSeeksToo() async throws {
        let url = try await environment.writePlayableMedia(hasVideo: false)
        _ = try await service.load(url) { _ in }

        try await service.seek(to: 0.5, precision: .exact)

        #expect(abs(service.currentTime - 0.5) < 0.05)
    }

    @Test func aRecordingCanPlayAgainAfterSeekingBackFromTheEnd() async throws {
        let url = try await environment.writePlayableMedia(hasVideo: true)
        let log = EventLog()
        _ = try await service.load(url) { log.events.append($0) }
        service.play()
        try await waitUntil { log.hasEnded }
        log.events = []

        try await service.seek(to: 0.5, precision: .exact)
        service.play()
        try await waitUntil { log.hasEnded }

        #expect(log.hasEnded)
    }

    @Test func seekingWithNothingLoadedFails() async {
        await #expect(throws: PlaybackFailure.seekFailed) {
            try await service.seek(to: 1, precision: .exact)
        }
    }

    @Test func unloadingStopsReportsAndFreesTheItem() async throws {
        let url = try await environment.writePlayableMedia(hasVideo: true)
        let log = EventLog()
        _ = try await service.load(url) { log.events.append($0) }
        service.play()
        try await waitUntil { !log.events.isEmpty }

        service.unload()
        let countAfterUnload = log.events.count
        try await Task.sleep(for: .milliseconds(300))

        #expect(log.events.count == countAfterUnload)
        #expect(service.player.currentItem == nil)
        #expect(service.player.rate == 0)
        #expect(service.currentTime == 0)
    }

    @Test func loadingAnotherRecordingStartsAtTheBeginningAndSilencesTheFirst() async throws {
        let first = try await environment.writePlayableMedia(hasVideo: true)
        let second = try await environment.writePlayableMedia(hasVideo: false)
        let firstLog = EventLog()
        _ = try await service.load(first) { firstLog.events.append($0) }
        try await service.seek(to: 0.5, precision: .exact)
        service.play()

        let info = try await service.load(second) { _ in }
        let countAfterSwitch = firstLog.events.count
        try await Task.sleep(for: .milliseconds(300))

        #expect(!info.hasVideo)
        #expect(service.currentTime == 0)
        #expect(service.player.rate == 0)
        #expect(firstLog.events.count == countAfterSwitch)
    }

    @Test func anOvertakenLoadIsCancelled() async throws {
        let first = try await environment.writePlayableMedia(hasVideo: true)
        let second = try await environment.writePlayableMedia(hasVideo: false)

        let service = service
        let overtaken = Task { try await service.load(first) { _ in } }
        await Task.yield()
        let info = try await service.load(second) { _ in }

        await #expect(throws: CancellationError.self) {
            _ = try await overtaken.value
        }
        #expect(!info.hasVideo)
    }

    @Test func aFileThatIsNotMediaFails() async throws {
        let url = environment.root.appending(path: "garbage.mov")
        try Data(repeating: 0x41, count: 4_096).write(to: url)

        await #expect {
            _ = try await service.load(url) { _ in }
        } throws: { error in
            guard let failure = error as? PlaybackFailure else {
                return false
            }
            return failure == .corruptedMedia || failure == .unsupportedFormat
        }
    }

    @Test func aTruncatedRecordingFailsWithoutCrashing() async throws {
        let url = try await environment.writePlayableMedia(hasVideo: true)
        let data = try Data(contentsOf: url)
        let truncated = environment.root.appending(path: "truncated.mov")
        try data.prefix(64).write(to: truncated)

        await #expect(throws: PlaybackFailure.self) {
            _ = try await service.load(truncated) { _ in }
        }
    }

    @Test func aMissingFileFails() async throws {
        let url = environment.root.appending(path: "nothing-here.mov")

        await #expect(throws: PlaybackFailure.self) {
            _ = try await service.load(url) { _ in }
        }
    }

    @Test func aFailedLoadLeavesThePlayerUsable() async throws {
        let garbage = environment.root.appending(path: "garbage.mov")
        try Data(repeating: 0x41, count: 4_096).write(to: garbage)
        await #expect(throws: PlaybackFailure.self) {
            _ = try await service.load(garbage) { _ in }
        }
        let url = try await environment.writePlayableMedia(hasVideo: true)

        let info = try await service.load(url) { _ in }

        #expect(info.hasVideo)
    }

    @Test(arguments: [
        (AVError.Code.fileFormatNotRecognized.rawValue, PlaybackFailure.unsupportedFormat),
        (AVError.Code.decoderNotFound.rawValue, .unsupportedFormat),
        (AVError.Code.fileFailedToParse.rawValue, .corruptedMedia),
        (AVError.Code.decodeFailed.rawValue, .corruptedMedia)
    ])
    func avFoundationErrorsTranslate(code: Int, expected: PlaybackFailure) {
        let error = NSError(domain: AVFoundationErrorDomain, code: code)

        #expect(PlaybackFailure(mediaError: error) == expected)
    }

    @Test func theCauseIsFoundInsideAWrappingError() {
        let cause = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        let wrapped = NSError(domain: "Wrapper", code: 1, userInfo: [NSUnderlyingErrorKey: cause])

        #expect(PlaybackFailure(mediaError: wrapped) == .mediaUnavailable(.accessDenied))
    }

    @Test func aMissingFileErrorTranslates() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist)

        #expect(PlaybackFailure(mediaError: error) == .mediaUnavailable(.missing))
    }
}

/// Opening media for playback through the real file store.
struct OpenMediaFileTests {
    @Test func opensTheStoredFile() async throws {
        let environment = try LibraryTestEnvironment()
        let store = environment.makeFileStore()
        let recording = try environment.makeRecording()

        let media = try await store.openMedia(of: recording)
        defer { media.close() }

        #expect(media.url == recording.media.url)
    }

    @Test func followsAFileMovedInFinder() async throws {
        let environment = try LibraryTestEnvironment()
        let store = environment.makeFileStore()
        let recording = try environment.makeRecording()
        let moved = environment.root.appending(path: "moved.mov")
        try FileManager.default.moveItem(at: recording.media.url, to: moved)

        let media = try await store.openMedia(of: recording)
        defer { media.close() }

        #expect(media.url.lastPathComponent == "moved.mov")
    }

    @Test func refusesAMissingFile() async throws {
        let environment = try LibraryTestEnvironment()
        let store = environment.makeFileStore()
        var recording = try environment.makeRecording()
        try FileManager.default.removeItem(at: recording.media.url)
        recording.media.bookmark = nil

        await #expect(throws: LibraryError.mediaUnavailable(.missing)) {
            _ = try await store.openMedia(of: recording)
        }
    }

    @Test func revealingARelatedFileRequiresItToExist() async throws {
        let environment = try LibraryTestEnvironment()
        let store = environment.makeFileStore()
        let recording = try environment.makeRecording()

        await #expect(throws: LibraryError.mediaUnavailable(.missing)) {
            try await store.revealFile(named: "transcript.txt", besideMediaOf: recording)
        }
    }
}
