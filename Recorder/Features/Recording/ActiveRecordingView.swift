import SwiftUI

/// The Recording state: live timer, source summary, audio levels, and Pause and Stop actions.
/// Closing the window does not stop capture; reopening it shows this state.
struct ActiveRecordingView: View {
    @Bindable var viewModel: RecorderViewModel
    let clock: RecordingClock

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                RecordingIndicator(isPaused: clock.isPaused)
                ElapsedTimeView(clock: clock)
                sourceSummary
            }
            .padding(.horizontal, RecorderLayout.horizontalPadding)
            .padding(.top, 20)
            .padding(.bottom, 22)

            VStack(spacing: RecorderLayout.sectionSpacing) {
                audioLevels
                notes
            }
            .padding(.horizontal, RecorderLayout.horizontalPadding)

            Spacer(minLength: 0)

            controls
        }
    }

    private var sourceSummary: some View {
        HStack(spacing: 6) {
            IconView(sourceIcon, size: 13)
            Text(sourceDescription)
        }
        .font(.system(size: 12))
        .foregroundStyle(VerbatimColor.secondaryText)
        .accessibilityElement(children: .combine)
    }

    private var audioLevels: some View {
        GroupedSection {
            HStack(spacing: 10) {
                IconTile(icon: viewModel.isMicrophoneActive ? .microphone : .microphoneOff, tint: VerbatimColor.orange)
                Text("Microphone \(deviceSuffix)")
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                AudioSourceLevelMeter(
                    viewModel: viewModel,
                    source: .microphone,
                    isActive: viewModel.isMicrophoneActive && !clock.isPaused,
                    accessibilityLabel: "Microphone level"
                )
                sourceState(isOn: viewModel.isMicrophoneActive)
            }
            .audioRowLayout()

            GroupedDivider(leadingInset: 44)

            HStack(spacing: 10) {
                IconTile(icon: .volume, tint: VerbatimColor.pink)
                Text("System Audio")
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                AudioSourceLevelMeter(
                    viewModel: viewModel,
                    source: .systemAudio,
                    isActive: viewModel.isSystemAudioActive && !clock.isPaused,
                    accessibilityLabel: "System audio activity"
                )
                sourceState(isOn: viewModel.isSystemAudioActive)
            }
            .audioRowLayout()
        }
    }

    private var deviceSuffix: Text {
        Text(verbatim: "· \(viewModel.activeMicrophoneName)")
            .foregroundStyle(VerbatimColor.secondaryText)
    }

    private func sourceState(isOn: Bool) -> some View {
        Text(isOn ? "On" : "Off")
            .font(.system(size: 12))
            .foregroundStyle(VerbatimColor.secondaryText)
            .frame(width: 24, alignment: .trailing)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You can close this window. Recording continues and can be stopped from the Dock or the menu bar.")
                .fixedSize(horizontal: false, vertical: true)
            // Shown for design review only until a processing queue exists to actually pause.
            if let pausedTranscriptionTitle = viewModel.preview.pausedTranscriptionTitle {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    IconView(.pause, size: 13)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                    Text("Transcription of “\(pausedTranscriptionTitle)” is paused and resumes when you stop.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.system(size: 12))
        .lineSpacing(2.5)
        .foregroundStyle(VerbatimColor.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var controls: some View {
        HStack(spacing: Self.controlSpacing) {
            Button {
                viewModel.togglePause()
            } label: {
                HStack(spacing: 8) {
                    IconView(clock.isPaused ? .play : .pause, size: 14)
                    Text(clock.isPaused ? "Resume" : "Pause")
                }
            }
            .buttonStyle(.verbatim(.secondary, size: .large))
            .frame(width: Self.pauseButtonWidth)
            .disabled(isFinishing)

            Button {
                viewModel.stopRecording()
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .frame(width: 11, height: 11)
                    Text(isFinishing ? "Saving…" : "Stop Recording")
                    Text("⌘⇧R")
                        .font(.system(size: 12, weight: .regular))
                        .opacity(0.8)
                        .padding(.leading, 4)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.verbatim(.record, size: .large))
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(isFinishing)
        }
        .padding(.horizontal, RecorderLayout.horizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    private var isFinishing: Bool {
        if case .finishing = viewModel.phase {
            return true
        }
        return false
    }

    private var sourceIcon: VerbatimIcon {
        switch viewModel.activeCaptureMode {
        case .screen: .monitor
        case .window: .window
        case .audioOnly: .audio
        }
    }

    private var sourceDescription: String {
        guard viewModel.activeCaptureMode == .audioOnly else {
            return "\(viewModel.activeSourceName) · \(viewModel.activeVideoSummary)"
        }
        var sources: [String] = []
        if viewModel.isMicrophoneActive {
            sources.append(String(localized: "Microphone"))
        }
        if viewModel.isSystemAudioActive {
            sources.append(String(localized: "System Audio"))
        }
        let audioOnly = String(localized: "Audio only")
        return "\(audioOnly) · \(sources.joined(separator: " + "))"
    }

    /// The design splits the footer one third Pause, two thirds Stop.
    private static let controlSpacing: CGFloat = 10
    private static let pauseButtonWidth = (RecorderLayout.contentWidth - controlSpacing) / 3
}

/// “Recording” with a blinking red dot, or a steady gray dot and “Paused”.
private struct RecordingIndicator: View {
    let isPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            if isPaused || reduceMotion {
                dot(isVisible: true)
            } else {
                TimelineView(.periodic(from: .now, by: SimulatedAudioLevels.tickInterval)) { context in
                    dot(isVisible: Self.isBlinkVisible(at: context.date))
                }
            }
            Text(isPaused ? "Paused" : "Recording")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(isPaused ? VerbatimColor.secondaryText : VerbatimColor.red)
        .accessibilityElement(children: .combine)
    }

    private func dot(isVisible: Bool) -> some View {
        Circle()
            .fill(isPaused ? VerbatimColor.tertiaryText : VerbatimColor.red)
            .opacity(isVisible ? 1 : 0)
            .frame(width: 8, height: 8)
            .animation(.easeInOut(duration: 0.3), value: isVisible)
    }

    /// On for five ticks, off for three, as in the design prototype.
    private static func isBlinkVisible(at date: Date) -> Bool {
        let tick = Int(date.timeIntervalSinceReferenceDate / SimulatedAudioLevels.tickInterval)
        return tick % 8 < 5
    }
}

/// The large `HH:MM:SS` timer, updated live unless paused.
private struct ElapsedTimeView: View {
    let clock: RecordingClock

    var body: some View {
        if clock.isPaused {
            timer(at: .now)
        } else {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                timer(at: context.date)
            }
        }
    }

    private func timer(at date: Date) -> some View {
        let elapsed = clock.elapsed(at: date)
        return Text(RecordingClock.timerText(for: elapsed))
            .font(.system(size: 64, weight: .light))
            .monospacedDigit()
            .tracking(-1.28)
            .accessibilityLabel("Elapsed time")
            .accessibilityValue(
                Duration.seconds(Int(elapsed)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
            )
    }
}
