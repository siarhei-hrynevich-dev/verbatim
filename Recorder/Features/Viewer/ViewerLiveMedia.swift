import SwiftUI

/// A real recording's picture: the injected video surface, letterboxed on black, with a play or replay button over it
/// while stopped. A click anywhere toggles playback.
struct ViewerLiveVideo: View {
    let viewModel: ViewerViewModel
    let surface: AnyView
    let activate: () -> Void

    var body: some View {
        ZStack {
            Color.black
            // The surface would otherwise take the clicks and keyboard focus the player's overlay handles.
            surface.allowsHitTesting(false)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.togglePlayback()
                    activate()
                }
            switch viewModel.playbackState {
            case .ready, .paused:
                ViewerPlayOverlay(systemImage: "play.fill")
                    .allowsHitTesting(false)
            case .ended:
                ViewerPlayOverlay(systemImage: "arrow.counterclockwise")
                    .allowsHitTesting(false)
            case .idle, .loading, .playing, .failed:
                EmptyView()
            }
        }
        .accessibilityHidden(true)
    }
}

/// The button shape shown over a stopped video.
struct ViewerPlayOverlay: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 26))
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(.ultraThinMaterial, in: Circle())
            .background(Color(white: 40 / 255).opacity(0.7), in: Circle())
            .environment(\.colorScheme, .dark)
    }
}

/// A real audio-only recording: its title, what the file holds, and the time. The controls are in the shared HUD.
struct ViewerLiveAudio: View {
    let viewModel: ViewerViewModel
    let recording: ViewerRecording

    var body: some View {
        VStack(spacing: 10) {
            IconView(.audio, size: 44)
                .foregroundStyle(VerbatimColor.accent)
            Text(viewModel.title)
                .font(.system(size: 17, weight: .bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(trackSummary)
                .font(.system(size: 12))
                .foregroundStyle(VerbatimColor.secondaryText)
            ViewerLiveAudioClock(viewModel: viewModel)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VerbatimColor.contentBackground)
    }

    private var trackSummary: String {
        guard let count = viewModel.mediaInfo?.audioTrackCount else {
            return recording.item.kindLabel
        }
        let tracks = LibraryFormat.count(
            count,
            singular: String(localized: "track"),
            plural: String(localized: "tracks")
        )
        return "\(recording.item.kindLabel) · \(tracks)"
    }
}

/// Its own view so that the many position updates redraw only this text.
private struct ViewerLiveAudioClock: View {
    let viewModel: ViewerViewModel

    var body: some View {
        let elapsed = RecordingClock.timerText(for: viewModel.position)
        let total = RecordingClock.timerText(for: viewModel.duration)
        Text("\(elapsed) / \(total)")
            .font(.system(size: 13))
            .monospacedDigit()
            .foregroundStyle(VerbatimColor.secondaryText)
            .padding(.top, 6)
            .accessibilityLabel("Elapsed \(elapsed) of \(total)")
    }
}

/// Why the recording can't play, in place of the media, with what can be done about it.
struct ViewerPlaybackErrorView: View {
    let issue: ViewerIssue
    let perform: (ViewerIssue.Recovery) -> Void
    let backToLibrary: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            IconView(.missingFile, size: 36)
                .foregroundStyle(VerbatimColor.tertiaryText)
            Text(issue.title)
                .font(.system(size: 15, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
            Text(issue.message)
                .font(.system(size: 12))
                .foregroundStyle(VerbatimColor.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(Array(issue.recoveries.enumerated()), id: \.element) { index, recovery in
                    Button(recovery.title) { perform(recovery) }
                        .buttonStyle(.verbatim(index == 0 ? .accent : .secondary, size: .regular))
                }
                if issue.recoveries.isEmpty {
                    Button("Back to Library", action: backToLibrary)
                        .buttonStyle(.verbatim(.accent, size: .regular))
                }
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VerbatimColor.contentBackground)
    }
}

/// Shown when the window is open with no recording, such as from the Window menu.
struct ViewerNothingOpenView: View {
    let backToLibrary: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            IconView(.file, size: 36)
                .foregroundStyle(VerbatimColor.tertiaryText)
            Text("No recording open")
                .font(.system(size: 15, weight: .bold))
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
            Text("Choose a recording in the Library to play it.")
                .font(.system(size: 12))
                .foregroundStyle(VerbatimColor.secondaryText)
            Button("Open Library", action: backToLibrary)
                .buttonStyle(.verbatim(.accent, size: .regular))
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VerbatimColor.contentBackground)
    }
}
