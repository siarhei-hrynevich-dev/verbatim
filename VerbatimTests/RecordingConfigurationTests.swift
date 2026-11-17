import Foundation
import Testing

@testable import Verbatim

struct VideoDimensionsTests {
    @Test(arguments: [
        // 16:9 sources land exactly on each preset.
        (VideoQuality.hd720, PixelSize(width: 3840, height: 2160), PixelSize(width: 1280, height: 720)),
        (.hd1080, PixelSize(width: 3840, height: 2160), PixelSize(width: 1920, height: 1080)),
        // A MacBook's 16:10-ish panel is limited by height, keeping its shape.
        (.hd1080, PixelSize(width: 3024, height: 1964), PixelSize(width: 1662, height: 1080)),
        // An ultrawide is limited by width.
        (.hd720, PixelSize(width: 3440, height: 1440), PixelSize(width: 1280, height: 536)),
        // A portrait display stays portrait.
        (.hd1080, PixelSize(width: 1440, height: 2560), PixelSize(width: 608, height: 1080)),
        // Small sources are never upscaled.
        (.hd1080, PixelSize(width: 800, height: 600), PixelSize(width: 800, height: 600)),
        // Native keeps Retina pixels, only made even for the encoder.
        (.native, PixelSize(width: 5120, height: 2880), PixelSize(width: 5120, height: 2880)),
        (.native, PixelSize(width: 1281, height: 721), PixelSize(width: 1282, height: 722))
    ])
    func fitsTheBoxAndKeepsAspectRatio(quality: VideoQuality, source: PixelSize, expected: PixelSize) {
        #expect(quality.outputSize(forSource: source) == expected)
    }

    @Test func degenerateSourceStillGivesAnEncodableSize() {
        #expect(
            VideoQuality.native.outputSize(forSource: PixelSize(width: 0, height: 0)) == PixelSize(width: 2, height: 2)
        )
    }

    @Test func bitRateMatchesTheDesignEstimate() {
        let rate = VideoEncodingProfile.averageBitRate(for: PixelSize(width: 1920, height: 1080), frameRate: .fps60)
        #expect((17_000_000...20_000_000).contains(rate))
    }
}

struct RecordingConfigurationTests {
    @Test func requiresASelectedSource() {
        #expect(throws: RecordingFailure.noCaptureSourceSelected) {
            try TestFixtures.configuration(target: nil).validate()
        }
    }

    @Test func audioOnlyRequiresAnAudioSource() throws {
        #expect(throws: RecordingFailure.noEnabledSource) {
            try TestFixtures.configuration(target: .audioOnly, microphone: nil, capturesSystemAudio: false).validate()
        }
        try TestFixtures.configuration(target: .audioOnly, capturesSystemAudio: false).validate()
        try TestFixtures.configuration(target: .audioOnly, microphone: nil).validate()
    }

    @Test func videoNeedsNoAudioSource() throws {
        try TestFixtures.configuration(microphone: nil, capturesSystemAudio: false).validate()
    }

    @Test func permissionsFollowTheSources() {
        let microphoneOnly = TestFixtures.configuration(target: .audioOnly, capturesSystemAudio: false)
        #expect(!microphoneOnly.requiresScreenCaptureAccess)
        #expect(microphoneOnly.requiresMicrophoneAccess)

        let systemAudioOnly = TestFixtures.configuration(target: .audioOnly, microphone: nil)
        #expect(systemAudioOnly.requiresScreenCaptureAccess)
        #expect(!systemAudioOnly.requiresMicrophoneAccess)

        #expect(TestFixtures.configuration(microphone: nil, capturesSystemAudio: false).requiresScreenCaptureAccess)
    }

    @Test func diskPolicySeparatesLowFromInsufficient() {
        let bytesPerSecond: Int64 = 2_000_000
        #expect(DiskSpacePolicy.assess(freeBytes: 100_000_000, bytesPerSecond: bytesPerSecond) == .insufficient)
        #expect(
            DiskSpacePolicy.assess(freeBytes: 1_200_000_000, bytesPerSecond: bytesPerSecond)
                == .low(minutesRemaining: 10)
        )
        #expect(DiskSpacePolicy.assess(freeBytes: 200_000_000_000, bytesPerSecond: bytesPerSecond) == .sufficient)
    }

    @Test(arguments: [(0.0, 0.0), (1.0, 1.0), (0.1, 0.6), (-1.0, 0.0)])
    func levelsFollowTheDecibelScale(rms: Double, expected: Double) {
        #expect(abs(AudioLevels.normalized(rms: rms) - expected) < 0.001)
    }
}

struct RecordingFileLayoutTests {
    private let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00CF4FC964FF") ?? UUID()

    @Test func directoryNameSortsByTimeAndIsUnique() throws {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let date = Date(timeIntervalSince1970: 1_793_793_600)

        let name = RecordingFileLayout.directoryName(createdAt: date, id: id, timeZone: timeZone)

        #expect(name == "2026-11-04_120000_6f9619ff-8b86-d011-b42d-00cf4fc964ff")
        #expect(name != RecordingFileLayout.directoryName(createdAt: date, id: UUID(), timeZone: timeZone))
    }

    @Test func mediaKeepsItsNameInEveryRecordingFolder() {
        #expect(RecordingFileLayout.mediaFileName == "recording.mov")
    }
}
