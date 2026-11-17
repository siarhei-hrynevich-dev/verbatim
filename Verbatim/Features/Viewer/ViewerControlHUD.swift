import AppKit
import SwiftUI

/// The floating playback controls: volume, skip, play or pause, speed, full screen, and the position slider.
/// The HUD is dark in both appearances.
struct ViewerControlHUD: View {
    let viewModel: ViewerViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Button(action: viewModel.toggleMute) {
                    muteIcon
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(HUDButtonStyle())
                .opacity(0.85)
                .help(viewModel.isMuted ? "Unmute" : "Mute")
                .accessibilityLabel(viewModel.isMuted ? "Unmute" : "Mute")
                VolumeSlider(viewModel: viewModel)
                Spacer(minLength: 0)
                skipButton("−15", label: "Back 15 seconds", seconds: -ViewerPlayerView.skipSeconds)
                Button(action: viewModel.togglePlayback) {
                    Image(systemName: playButtonImage)
                        .font(.system(size: 20))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(HUDButtonStyle())
                .accessibilityLabel(playButtonLabel)
                .disabled(!isTransportEnabled)
                skipButton("+15", label: "Forward 15 seconds", seconds: ViewerPlayerView.skipSeconds)
                Spacer(minLength: 0)
                speedButton
                if viewModel.showsVideo {
                    Button {
                        NSApp.keyWindow?.toggleFullScreen(nil)
                    } label: {
                        IconView(.maximize, size: 15)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(HUDButtonStyle())
                    .opacity(0.85)
                    .help("Full Screen")
                    .accessibilityLabel("Full Screen")
                }
            }
            PlaybackSlider(viewModel: viewModel)
                .disabled(!isTransportEnabled)
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

    @ViewBuilder
    private var muteIcon: some View {
        if viewModel.isMuted {
            Image(systemName: "speaker.slash")
                .font(.system(size: 13))
        } else {
            IconView(.volume, size: 15)
        }
    }

    /// Design scenarios have no loaded media, and their simulated clock runs regardless.
    private var isTransportEnabled: Bool {
        viewModel.isPreviewing || viewModel.canControlPlayback
    }

    private var playButtonImage: String {
        switch viewModel.playbackState {
        case .playing: "pause.fill"
        case .ended: "arrow.counterclockwise"
        case .idle, .loading, .ready, .paused, .failed: "play.fill"
        }
    }

    private var playButtonLabel: LocalizedStringKey {
        switch viewModel.playbackState {
        case .playing: "Pause"
        case .ended: "Replay"
        case .idle, .loading, .ready, .paused, .failed: "Play"
        }
    }

    private func skipButton(_ title: String, label: LocalizedStringKey, seconds: TimeInterval) -> some View {
        Button(title) { viewModel.skip(by: seconds) }
            .buttonStyle(HUDButtonStyle())
            .font(.system(size: 11, weight: .semibold))
            .opacity(0.85)
            .disabled(!isTransportEnabled)
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

/// The volume bar, in the shape of the design's: click or drag anywhere on it.
private struct VolumeSlider: View {
    let viewModel: ViewerViewModel

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.25))
            .frame(width: Self.width, height: 3)
            .overlay(alignment: .leading) {
                Capsule().fill(.white).frame(width: Self.width * shownVolume)
            }
            .frame(height: 14)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { viewModel.setVolume($0.location.x / Self.width) }
            )
            .accessibilityElement()
            .accessibilityLabel("Volume")
            .accessibilityValue(Text(shownVolume, format: .percent.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: viewModel.setVolume(viewModel.volume + Self.step)
                case .decrement: viewModel.setVolume(viewModel.volume - Self.step)
                @unknown default: break
                }
            }
    }

    private var shownVolume: Double {
        viewModel.isMuted ? 0 : viewModel.volume
    }

    private static let width: CGFloat = 56
    private static let step = 0.1
}

/// Elapsed time, the position bar and the remaining time. The bar is keyboard adjustable in 5 second steps. A drag owns
/// the position until it ends, and the model holds the thumb there against the player's own updates.
private struct PlaybackSlider: View {
    let viewModel: ViewerViewModel

    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isDragging = false
    /// Resets by itself when the system cancels the gesture, which never reports an end.
    @GestureState private var isGestureActive = false

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
                            .updating($isGestureActive) { _, isActive, _ in isActive = true }
                            .onChanged { value in drag(toX: value.location.x, width: proxy.size.width) }
                            .onEnded { value in endDrag(atX: value.location.x, width: proxy.size.width) }
                    )
                    .onChange(of: isGestureActive) { _, isActive in
                        if !isActive, isDragging {
                            isDragging = false
                            viewModel.endScrubbing(at: viewModel.position)
                        }
                    }
                    .allowsHitTesting(isEnabled)
            }
            .frame(height: 14)
            .focusable()
            .focused($isFocused)
            .focusRing(cornerRadius: 4, isVisible: isFocused)
            .onKeyPress(.space) {
                viewModel.togglePlayback()
                return .handled
            }
            .onKeyPress(.leftArrow) {
                viewModel.skip(by: -Self.keyboardStep)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                viewModel.skip(by: Self.keyboardStep)
                return .handled
            }
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

    private func drag(toX offset: CGFloat, width: CGFloat) {
        if !isDragging {
            isDragging = true
            viewModel.beginScrubbing()
        }
        viewModel.scrub(to: position(atX: offset, width: width))
    }

    /// A quick click can arrive as an end with no change before it.
    private func endDrag(atX offset: CGFloat, width: CGFloat) {
        if !isDragging {
            viewModel.beginScrubbing()
        }
        isDragging = false
        viewModel.endScrubbing(at: position(atX: offset, width: width))
    }

    private func position(atX offset: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else {
            return viewModel.position
        }
        return min(max(offset / width, 0), 1) * viewModel.duration
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
