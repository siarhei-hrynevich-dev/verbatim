import SwiftUI

/// Borderless window-toolbar button: secondary text color with a fill on hover.
/// Icon-only buttons should be given a square 28 pt frame through their label.
struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToolbarButtonBody(configuration: configuration)
    }
}

extension ButtonStyle where Self == ToolbarButtonStyle {
    static var toolbarIcon: ToolbarButtonStyle {
        ToolbarButtonStyle()
    }
}

private struct ToolbarButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(VerbatimColor.secondaryText)
            .frame(minWidth: 28, minHeight: 28)
            .background(isHovered || configuration.isPressed ? VerbatimColor.fill : .clear, in: shape)
            .contentShape(shape)
            .focusRing(cornerRadius: 6)
            .onHover { isHovered = $0 }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 6)
    }
}

/// A button without chrome whose content draws its own selection state, such as a thumbnail tile.
/// It keeps keyboard focus visible with a ring around the whole tile.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .focusRing(cornerRadius: 8)
    }
}

extension ButtonStyle where Self == TileButtonStyle {
    static var tile: TileButtonStyle {
        TileButtonStyle()
    }
}
