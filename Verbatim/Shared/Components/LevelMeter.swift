import SwiftUI

/// An eight-segment audio level meter. Lit segments are green; the top two turn yellow.
struct LevelMeter: View {
    nonisolated static let segmentCount = 8

    /// Number of lit segments, clamped to `0...segmentCount`.
    let litSegments: Int
    let accessibilityLabel: LocalizedStringKey

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<Self.segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(forSegment: index))
                    .frame(width: 3, height: 10)
            }
        }
        .frame(width: 44, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text(levelPercent, format: .percent))
    }

    private var clampedLitSegments: Int {
        min(max(litSegments, 0), Self.segmentCount)
    }

    private var levelPercent: Double {
        Double(clampedLitSegments) / Double(Self.segmentCount)
    }

    private func color(forSegment index: Int) -> Color {
        guard index < clampedLitSegments else {
            return VerbatimColor.meterOff
        }
        return index > 5 ? VerbatimColor.yellow : VerbatimColor.green
    }
}
