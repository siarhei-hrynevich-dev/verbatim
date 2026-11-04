import SwiftUI

/// The meter for one audio source: live levels, or a simulated pattern while a design scenario is showing.
/// A separate view, so that level updates redraw only the meter.
struct AudioSourceLevelMeter: View {
    let viewModel: RecorderViewModel
    let source: AudioSourceKind
    let isActive: Bool
    let accessibilityLabel: LocalizedStringKey

    var body: some View {
        if viewModel.preview.isActive {
            SimulatedLevelMeter(
                isActive: isActive,
                seed: source == .microphone ? 1 : 4,
                accessibilityLabel: accessibilityLabel
            )
        } else {
            LevelMeter(
                litSegments: isActive ? viewModel.litSegments(for: source) : 0,
                accessibilityLabel: accessibilityLabel
            )
        }
    }
}

/// A level meter animated with simulated levels while active, for design review.
private struct SimulatedLevelMeter: View {
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
