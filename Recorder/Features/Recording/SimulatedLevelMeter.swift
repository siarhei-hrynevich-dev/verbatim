import SwiftUI

/// A level meter animated with simulated levels while active. Real input levels will replace the simulation.
struct SimulatedLevelMeter: View {
    let isActive: Bool
    let seed: Double
    let accessibilityLabel: LocalizedStringKey

    var body: some View {
        if isActive {
            TimelineView(.periodic(from: .now, by: SimulatedAudioLevels.tickInterval)) { context in
                LevelMeter(
                    litSegments: SimulatedAudioLevels.litSegments(at: context.date, seed: seed),
                    accessibilityLabel: accessibilityLabel
                )
            }
        } else {
            LevelMeter(litSegments: 0, accessibilityLabel: accessibilityLabel)
        }
    }
}
