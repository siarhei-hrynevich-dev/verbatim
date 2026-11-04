import SwiftUI

/// The player column: the video frame or audio tracks with the floating control HUD, and the folder strip below.
///
/// The player is a keyboard focus stop: Space plays or pauses, and Left and Right skip 15 seconds.
struct ViewerPlayerView: View {
    let viewModel: ViewerViewModel
    let openFolder: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                media
                ViewerControlHUD(viewModel: viewModel)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { keyboardTarget }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Player")

            ViewerFolderStrip(recording: viewModel.recording, openFolder: openFolder)
        }
    }

    /// Holds the player's keyboard focus behind the media and controls. Controls read the nearest focused
    /// ancestor as their own focus, so a focused container would ring every HUD button.
    private var keyboardTarget: some View {
        Color.clear
            .focusable(interactions: .edit)
            .focused($isFocused)
            .onKeyPress(.space) { handle(viewModel.togglePlayback) }
            .onKeyPress(.leftArrow) { handle { viewModel.skip(by: -ViewerPlayerView.skipSeconds) } }
            .onKeyPress(.rightArrow) { handle { viewModel.skip(by: ViewerPlayerView.skipSeconds) } }
            .onAppear { isFocused = true }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var media: some View {
        switch viewModel.recording.item.kind {
        case .screen, .window:
            VideoFrame(isPaused: !viewModel.isPlaying)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.togglePlayback()
                    isFocused = true
                }
                .accessibilityHidden(true)
        case .audio:
            ViewerWaveformView(viewModel: viewModel)
        }
    }

    private func handle(_ action: () -> Void) -> KeyPress.Result {
        action()
        return .handled
    }

    static let skipSeconds: TimeInterval = 15
}

/// A stylized frame of a screen recording on black, with a play button over it while paused.
private struct VideoFrame: View {
    let isPaused: Bool

    var body: some View {
        ZStack {
            Color.black
            GeometryReader { proxy in
                let size = proxy.size
                ZStack(alignment: .topLeading) {
                    Self.surface
                    Self.chrome.frame(height: size.height * 0.04)
                    Self.sidebar
                        .frame(width: size.width * 0.2, height: size.height * 0.96)
                        .offset(y: size.height * 0.04)
                    block(Self.line, CGRect(x: 0.25, y: 0.12, width: 0.4, height: 0.03), radius: 3, in: size)
                    block(Self.chrome, CGRect(x: 0.25, y: 0.2, width: 0.66, height: 0.44), radius: 8, in: size)
                    block(Self.line, CGRect(x: 0.25, y: 0.7, width: 0.52, height: 0.02), radius: 3, in: size)
                    block(Self.line, CGRect(x: 0.25, y: 0.75, width: 0.6, height: 0.02), radius: 3, in: size)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Self.line)
                        .frame(width: size.width * 0.18, height: size.width * 0.18 / 1.6)
                        .offset(x: size.width * 0.79, y: size.height * 0.96 - size.width * 0.18 / 1.6)
                    if isPaused {
                        playOverlay.position(x: size.width / 2, y: size.height * 0.42)
                    }
                }
            }
            .aspectRatio(1.54, contentMode: .fit)
            .clipped()
        }
    }

    /// A rounded block placed by fractions of the frame's size.
    private func block(_ color: Color, _ fraction: CGRect, radius: CGFloat, in size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(color)
            .frame(width: size.width * fraction.width, height: size.height * fraction.height)
            .offset(x: size.width * fraction.minX, y: size.height * fraction.minY)
    }

    private var playOverlay: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 26))
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(.ultraThinMaterial, in: Circle())
            .background(Color(white: 40 / 255).opacity(0.7), in: Circle())
            .environment(\.colorScheme, .dark)
    }

    // The frame shows a dark app window in both appearances.
    private static let surface = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private static let chrome = Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
    private static let sidebar = Color(red: 36 / 255, green: 36 / 255, blue: 38 / 255)
    private static let line = Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255)
}

/// The recording's folder and files. Transcript files are dimmed until they exist.
private struct ViewerFolderStrip: View {
    let recording: ViewerRecording
    let openFolder: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            IconView(.folder, size: 13)
                .foregroundStyle(VerbatimColor.accent)
            Text(recording.item.folderName)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(minWidth: 60, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(Array(chips.enumerated()), id: \.offset) { index, name in
                    fileChip(name, isAvailable: index == 0 || recording.hasTranscript)
                }
            }
            .fixedSize()
            Spacer(minLength: 0)
            Button("Open Folder", action: openFolder)
                .buttonStyle(.verbatim(.secondary, size: .small))
                .fixedSize()
        }
        .font(.system(size: 11))
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 36)
        .background(VerbatimColor.windowBackground)
        .overlay(alignment: .top) {
            VerbatimColor.separator.frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording folder")
    }

    /// `recording.mov  3.1 GB`, then the transcript files with their extensions shortened after the first.
    private var chips: [String] {
        let item = recording.item
        let media = "\(item.fileNames.first ?? "")  \(LibraryFormat.size(item.sizeBytes))"
        let transcripts = LibraryFormat.fileSummary(Array(item.fileNames.dropFirst()))
            .components(separatedBy: " · ")
        return [media] + transcripts
    }

    private func fileChip(_ name: String, isAvailable: Bool) -> some View {
        HStack(spacing: 4) {
            IconView(.file, size: 10)
            Text(name)
        }
        .foregroundStyle(VerbatimColor.secondaryText)
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(VerbatimColor.fill, in: Capsule())
        .opacity(isAvailable ? 1 : 0.4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isAvailable ? "" : String(localized: "Not available yet"))
    }
}
