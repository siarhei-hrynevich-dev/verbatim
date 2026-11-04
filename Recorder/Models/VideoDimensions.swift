import Foundation

/// A size in physical pixels, so Retina scaling is resolved before it reaches capture configuration.
struct PixelSize: Equatable, Sendable {
    let width: Int
    let height: Int

    var pixelCount: Int {
        width * height
    }
}

extension VideoQuality {
    /// The largest box the output must fit in, or `nil` to keep the source size.
    private var boundingBox: PixelSize? {
        switch self {
        case .hd720: PixelSize(width: 1280, height: 720)
        case .hd1080: PixelSize(width: 1920, height: 1080)
        case .native: nil
        }
    }

    /// The encoded size for a source: fits the quality's box, keeps the aspect ratio, and never upscales.
    /// Dimensions are even, as the video encoder requires.
    func outputSize(forSource source: PixelSize) -> PixelSize {
        guard source.width > 0, source.height > 0 else {
            return PixelSize(width: 2, height: 2)
        }
        var scale = 1.0
        if let boundingBox {
            scale = min(
                Double(boundingBox.width) / Double(source.width),
                Double(boundingBox.height) / Double(source.height),
                1
            )
        }
        return PixelSize(
            width: Self.evenDimension(Double(source.width) * scale),
            height: Self.evenDimension(Double(source.height) * scale)
        )
    }

    private static func evenDimension(_ value: Double) -> Int {
        max(Int((value / 2).rounded()) * 2, 2)
    }
}

/// Encoding targets shared by the writer and the disk space estimate.
enum VideoEncodingProfile {
    /// Screen content compressed with HEVC; about 18 Mbit/s at 1080p and 60 fps.
    static func averageBitRate(for size: PixelSize, frameRate: FrameRate) -> Int {
        Int(Double(size.pixelCount * frameRate.rawValue) * bitsPerPixel)
    }

    /// Stereo system audio plus mono microphone audio.
    static let audioBytesPerSecond: Int64 = 32_000

    private static let bitsPerPixel = 0.15
}
