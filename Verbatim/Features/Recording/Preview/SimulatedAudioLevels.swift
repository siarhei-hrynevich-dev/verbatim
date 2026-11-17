import Foundation

/// Simulated audio levels: a smooth, deterministic pattern derived from time, matching the design prototype.
enum SimulatedAudioLevels {
    /// The prototype advances its meters every 150 ms.
    static let tickInterval: TimeInterval = 0.15

    static func litSegments(at date: Date, seed: Double) -> Int {
        let tick = (date.timeIntervalSinceReferenceDate / tickInterval).rounded(.down)
        let wave = abs(sin(tick * 0.55 + seed) * cos(tick * 0.21 + seed))
        return Int((Double(LevelMeter.segmentCount) * (0.3 + 0.5 * wave)).rounded())
    }
}
