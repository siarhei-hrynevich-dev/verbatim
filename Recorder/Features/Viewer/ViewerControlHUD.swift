import AppKit
import SwiftUI

/// The floating playback controls: volume, skip, play or pause, speed, full screen, and the position slider.
/// The HUD is dark in both appearances.
struct ViewerControlHUD: View {
    let viewModel: ViewerViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                IconView(.volume, size: 15)
                    .opacity(0.85)
                volume
                Spacer(minLength: 0)
                skipButton("−15", label: "Back 15 seconds", seconds: -ViewerPlayerView.skipSeconds)
                Button(action: viewModel.togglePlayback) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(HUDButtonStyle())
                .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
                skipButton("+15", label: "Forward 15 seconds", seconds: ViewerPlayerView.skipSeconds)
                Spacer(minLength: 0)
                speedButton
                if viewModel.recording.item.kind == .screen {
                    Button {
                        NSApp.keyWindow?.toggleFullScreen(nil)
                    } label: {
                        IconView(.maximize, size: 15)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(HUDButtonStyle())
                    .opacity(0.85)
                    .accessibilityLabel("Full Screen")
                }
            }
            PlaybackSlider(viewModel: viewModel)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: 560)
        .background {
            RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 14).fill(Self.background)
        }
        .hairlineBorder(cornerRadius: 14, color: .white.opacity(0.12))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback controls")
    }

    private var volume: some View {
        Capsule()
            .fill(.white.opacity(0.25))
            .frame(width: 56, height: 3)
            .overlay(alignment: .leading) {
                Capsule().fill(.white).frame(width: 56 * 0.7)
            }
            .accessibilityElement()
            .accessibilityLabel("Volume")
            .accessibilityValue(Text(0.7, format: .percent))
    }

    private func skipButton(_ title: String, label: LocalizedStringKey, seconds: TimeInterval) -> some View {
        Button(title) { viewModel.skip(by: seconds) }
            .buttonStyle(HUDButtonStyle())
            .font(.system(size: 11, weight: .semibold))
            .opacity(0.85)
            .accessibilityLabel(label)
    }

    private var speedButton: some View {
        Button(action: viewModel.cycleSpeed) {
            Text(viewModel.speed.title)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(HUDButtonStyle())
        .accessibilityLabel("Playback speed")
        .accessibilityValue(viewModel.speed.title)
    }

    private static let background = Color(red: 40 / 255, green: 40 / 255, blue: 42 / 255).opacity(0.8)
}

/// Elapsed time, the position bar and the remaining time. The bar is keyboard adjustable in 5 second steps.
private struct PlaybackSlider: View {
    let viewModel: ViewerViewModel

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(RecordingClock.timerText(for: viewModel.position))
                .fixedSize()
                .frame(minWidth: 52, alignment: .leading)
            GeometryReader { proxy in
                track
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in seek(toX: value.location.x, width: proxy.size.width) }
                    )
            }
            .frame(height: 14)
            .focusable()
            .focused($isFocused)
            .focusRing(cornerRadius: 4, isVisible: isFocused)
            .accessibilityElement()
            .accessibilityLabel("Playback position")
            .accessibilityValue(RecordingClock.timerText(for: viewModel.position))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: viewModel.skip(by: Self.keyboardStep)
                case .decrement: viewModel.skip(by: -Self.keyboardStep)
                @unknown default: break
                }
            }
            Text("−\(RecordingClock.timerText(for: viewModel.duration - viewModel.position))")
                .opacity(0.7)
                .fixedSize()
                .frame(minWidth: 52, alignment: .trailing)
        }
        .font(.system(size: 11))
        .monospacedDigit()
    }

    private var track: some View {
        Capsule()
            .fill(.white.opacity(0.25))
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(.white)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .clipShape(Capsule())
    }

    private var fraction: CGFloat {
        viewModel.duration > 0 ? viewModel.position / viewModel.duration : 0
    }

    private func seek(toX offset: CGFloat, width: CGFloat) {
        guard width > 0 else {
            return
        }
        viewModel.seek(to: min(max(offset / width, 0), 1) * viewModel.duration)
    }

    private static let keyboardStep: TimeInterval = 5
}

/// A chromeless HUD control that dims while pressed and keeps keyboard focus visible.
private struct HUDButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .focusRing(cornerRadius: 6)
    }
}

extension ViewerViewModel.PlaybackSpeed {
    var title: String {
        "\(rawValue.formatted(.number.precision(.fractionLength(0...1))))×"
    }
}
