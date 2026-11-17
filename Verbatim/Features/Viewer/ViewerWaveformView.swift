import SwiftUI

/// Audio-only recordings in design scenarios: the microphone and system audio drawn as separate tracks, matching the
/// transcript's You and System Audio labels. Click or drag across the tracks to seek.
struct ViewerWaveformView: View {
    let viewModel: ViewerViewModel
    let recording: ViewerRecording

    @State private var tracksWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Audio only · 2 tracks · AAC 48 kHz")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VerbatimColor.secondaryText)
            VStack(alignment: .leading, spacing: 18) {
                track(.you)
                track(.systemAudio)
            }
            .padding(.vertical, 8)
            .overlay { playhead }
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                tracksWidth = $0
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged(seek))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Audio tracks: You and System Audio")
            .accessibilityValue(RecordingClock.timerText(for: viewModel.position))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: viewModel.skip(by: 5)
                case .decrement: viewModel.skip(by: -5)
                @unknown default: break
                }
            }
        }
        .padding(.top, 32)
        .padding(.horizontal, 32)
        .padding(.bottom, 120)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VerbatimColor.contentBackground)
    }

    private func track(_ speaker: TranscriptLine.Speaker) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(speaker == .you ? VerbatimColor.orange : VerbatimColor.pink)
                    .frame(width: 18, height: 18)
                    .overlay {
                        IconView(speaker == .you ? .microphone : .volume, size: 11)
                            .foregroundStyle(.white)
                    }
                Text(speaker == .you ? "You · Microphone" : "System Audio")
            }
            .font(.system(size: 12, weight: .medium))

            WaveformBars(
                levels: Waveform.levels(for: speaker, in: recording),
                playedFraction: playedFraction
            )
            .frame(height: 80)
            .padding(.horizontal, 8)
            .background(VerbatimColor.fill, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var playhead: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 1)
                .fill(VerbatimColor.accent)
                .frame(width: 2)
                .offset(x: proxy.size.width * playedFraction)
        }
        .allowsHitTesting(false)
    }

    private func seek(_ value: DragGesture.Value) {
        guard tracksWidth > 0 else {
            return
        }
        let fraction = min(max(value.location.x / tracksWidth, 0), 1)
        viewModel.seek(to: fraction * recording.waveformSpan)
    }

    /// The tracks are drawn across the span the transcript covers; the playhead uses the same scale.
    private var playedFraction: CGFloat {
        let span = recording.waveformSpan
        return span > 0 ? min(viewModel.position / span, 1) : 0
    }
}

/// Bars of one track: played bars in the accent color, the rest in tertiary text.
private struct WaveformBars: View {
    let levels: [Double]
    let playedFraction: CGFloat

    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 2
            let barWidth = (size.width - gap * CGFloat(levels.count - 1)) / CGFloat(levels.count)
            for (index, level) in levels.enumerated() {
                let height = size.height * level
                let leading = CGFloat(index) * (barWidth + gap)
                let bar = CGRect(x: leading, y: (size.height - height) / 2, width: barWidth, height: height)
                let isPlayed = (CGFloat(index) / CGFloat(levels.count)) <= playedFraction
                context.fill(
                    Path(roundedRect: bar, cornerRadius: 1),
                    with: .style(isPlayed ? AnyShapeStyle(.tint) : AnyShapeStyle(VerbatimColor.tertiaryText))
                )
            }
        }
    }
}

/// Simulated track levels, matching the design prototype: a track is loud while its speaker talks and near
/// silent otherwise.
enum Waveform {
    static let barCount = 110

    static func levels(for speaker: TranscriptLine.Speaker, in recording: ViewerRecording) -> [Double] {
        let span = recording.waveformSpan
        let trackOffset: Double = speaker == .you ? 0 : 1
        return (0..<barCount).map { index in
            let bar = Double(index)
            let second = bar / Double(barCount) * span
            let speaking = recording.transcript.last { $0.start <= second }?.speaker == speaker
            guard speaking else {
                return 0.05 + 0.06 * abs(sin(bar * 2.1))
            }
            return 0.35 + 0.6 * abs(sin(bar * 1.37 + trackOffset) * cos(bar * 0.41 + trackOffset * 2))
        }
    }
}
