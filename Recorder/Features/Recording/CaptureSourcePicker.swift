import AppKit
import SwiftUI

/// Shows the choices for the selected capture mode: display thumbnails, window thumbnails, or an Audio Only note.
/// The selected thumbnail gets an accent ring and a bold name, so selection does not rely on color alone.
struct CaptureSourcePicker: View {
    @Bindable var viewModel: RecorderViewModel

    var body: some View {
        switch viewModel.captureMode {
        case .screen:
            displayGrid
        case .window:
            windowGrid
        case .audioOnly:
            audioOnlyNote
        }
    }

    private var displayGrid: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(viewModel.selection.displays) { display in
                let isSelected = display.id == viewModel.selectedDisplay?.id
                Button {
                    viewModel.selection.selectedDisplayID = display.id
                } label: {
                    VStack(spacing: 6) {
                        DisplayThumbnail(isSelected: isSelected)
                        VStack(spacing: 1) {
                            Text(display.name)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            Text(verbatim: "\(display.pixelWidth) × \(display.pixelHeight)")
                                .font(.system(size: 11))
                                .foregroundStyle(VerbatimColor.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tile)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Displays")
    }

    /// Two rows fit without scrolling, as in the design; more windows scroll within the same height.
    @ViewBuilder
    private var windowGrid: some View {
        if viewModel.selection.windows.isEmpty {
            note(icon: .window, "No windows are available to record. Open a window, or record the entire screen.")
        } else if viewModel.selection.windows.count > Self.windowsWithoutScrolling {
            ScrollView {
                windowTiles
                    .padding(Self.selectionRingOutset)
            }
            .padding(-Self.selectionRingOutset)
            .frame(height: Self.scrollingGridHeight)
        } else {
            windowTiles
        }
    }

    private var windowTiles: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(viewModel.selection.windows) { window in
                let isSelected = window.id == viewModel.selection.selectedWindowID
                Button {
                    viewModel.selection.selectedWindowID = window.id
                } label: {
                    VStack(spacing: 5) {
                        WindowThumbnail(
                            imageData: viewModel.selection.windowThumbnails[window.id],
                            isSelected: isSelected
                        )
                        VStack(spacing: 0) {
                            Text(window.appName)
                                .fontWeight(isSelected ? .semibold : .medium)
                                .lineLimit(1)
                            Text(window.title)
                                .foregroundStyle(VerbatimColor.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .font(.system(size: 11))
                    }
                }
                .buttonStyle(.tile)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Windows")
    }

    private var audioOnlyNote: some View {
        note(
            icon: .audio,
            """
            No video is captured. Microphone and system audio are saved as separate tracks, so the transcript \
            can label who spoke.
            """
        )
    }

    private func note(icon: VerbatimIcon, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            IconView(icon, size: 18)
                .foregroundStyle(VerbatimColor.accent)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
        .lineSpacing(1.5)
        .foregroundStyle(VerbatimColor.secondaryText)
        .padding(14)
        .groupedBackground()
    }

    private static let windowsWithoutScrolling = 6
    /// Keeps the selection ring, which is drawn outside a tile, from being clipped by the scroll view.
    private static let selectionRingOutset: CGFloat = 4
    /// Two rows of tiles and the space between them.
    private static let scrollingGridHeight: CGFloat = 190
}

/// A stylized display preview: a menu bar strip with two overlapping windows.
private struct DisplayThumbnail: View {
    let isSelected: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                VerbatimColor.thumbnail
                VerbatimColor.thumbnailBar
                    .frame(height: 7)
                RoundedRectangle(cornerRadius: 4)
                    .fill(VerbatimColor.thumbnailWindow)
                    .frame(width: size.width * 0.46, height: size.height * 0.56)
                    .offset(x: size.width * 0.12, y: size.height * 0.22)
                RoundedRectangle(cornerRadius: 4)
                    .fill(VerbatimColor.thumbnailWindowAlternate)
                    .frame(width: size.width * 0.38, height: size.height * 0.48)
                    .offset(x: size.width * 0.5, y: size.height * 0.34)
            }
        }
        .frame(height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .selectionRing(isSelected: isSelected, cornerRadius: 7)
    }
}

/// A window's real thumbnail when one is available, otherwise a stylized preview: a title bar strip with two text
/// lines.
private struct WindowThumbnail: View {
    let imageData: Data?
    let isSelected: Bool

    var body: some View {
        GeometryReader { proxy in
            if let imageData, let image = NSImage(data: imageData) {
                ZStack {
                    VerbatimColor.thumbnail
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                }
                .accessibilityHidden(true)
            } else {
                placeholder(width: proxy.size.width)
            }
        }
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .selectionRing(isSelected: isSelected, cornerRadius: 6)
    }

    private func placeholder(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            VerbatimColor.thumbnailWindow
            VerbatimColor.thumbnailBar
                .frame(height: 8)
            RoundedRectangle(cornerRadius: 2)
                .fill(VerbatimColor.thumbnail)
                .frame(width: width * 0.4, height: 4)
                .offset(x: 8, y: 16)
            RoundedRectangle(cornerRadius: 2)
                .fill(VerbatimColor.thumbnailWindowAlternate)
                .frame(width: width * 0.6, height: 4)
                .offset(x: 8, y: 25)
        }
    }
}

extension View {
    /// Draws a 3 pt accent ring outside the shape when selected, otherwise a hairline outline.
    fileprivate func selectionRing(isSelected: Bool, cornerRadius: CGFloat) -> some View {
        overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: cornerRadius + 1.5)
                    .stroke(VerbatimColor.accent, lineWidth: 3)
                    .padding(-1.5)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(VerbatimColor.separator, lineWidth: 0.5)
            }
        }
    }
}
