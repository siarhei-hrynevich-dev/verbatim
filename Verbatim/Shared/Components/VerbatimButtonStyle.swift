import SwiftUI

/// Filled push buttons of the Verbatim design.
///
/// Kinds: `accent` and `secondary` actions, `record` for the record action, and `destructive` for confirmed
/// deletions. Sizes, by height:
/// - `.small` (20 pt, 11 pt text): inline row and path bar actions.
/// - `.mini` (22 pt): an inline pop-up control, with room for a trailing chevron.
/// - `.inline` (22 pt, 12 pt text): actions inside a banner, such as Pause All.
/// - `.compact` (24 pt, 12 pt text): callout actions.
/// - `.dialog` (24 pt, 13 pt text): sheet and alert buttons.
/// - `.medium` (28 pt, 13 pt text): empty-state actions.
/// - `.regular` (26 pt, 12 pt text): panel actions, such as the Viewer's transcript actions.
/// - `.large` (40 pt): full-width window actions.
struct VerbatimButtonStyle: ButtonStyle {
    enum Kind {
        case accent
        case secondary
        case record
        case destructive
    }

    enum Size {
        case small
        case mini
        case inline
        case compact
        case dialog
        case medium
        case large
        case regular
    }

    let kind: Kind
    let size: Size

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(kind: kind, size: size, configuration: configuration)
    }
}

extension ButtonStyle where Self == VerbatimButtonStyle {
    static func verbatim(_ kind: VerbatimButtonStyle.Kind, size: VerbatimButtonStyle.Size) -> VerbatimButtonStyle {
        VerbatimButtonStyle(kind: kind, size: size)
    }
}

private struct StyledBody: View {
    let kind: VerbatimButtonStyle.Kind
    let size: VerbatimButtonStyle.Size
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let metrics = Metrics(size)
        let shape = RoundedRectangle(cornerRadius: metrics.cornerRadius)
        configuration.label
            .font(.system(size: metrics.fontSize, weight: fontWeight))
            .foregroundStyle(foreground)
            .padding(.leading, metrics.leadingPadding)
            .padding(.trailing, metrics.trailingPadding)
            .frame(maxWidth: size == .large ? .infinity : nil)
            .frame(height: metrics.height)
            .background(background, in: shape)
            .hairlineBorder(
                cornerRadius: metrics.cornerRadius,
                color: kind == .secondary ? VerbatimColor.separator : .clear
            )
            .shadow(color: .black.opacity(shadowOpacity), radius: size == .large ? 1 : 0.5, y: 1)
            .brightness(brightnessAdjustment)
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.4)
            .focusRing(cornerRadius: metrics.cornerRadius)
            .onHover { isHovered = $0 }
    }

    private var background: Color {
        switch kind {
        case .accent: VerbatimColor.accent
        case .secondary: VerbatimColor.controlBackground
        case .record, .destructive: VerbatimColor.red
        }
    }

    private var foreground: Color {
        kind == .secondary ? VerbatimColor.primaryText : .white
    }

    private var fontWeight: Font.Weight {
        switch (kind, size) {
        case (.record, .large): .semibold
        case (.secondary, .large): .medium
        case (.secondary, _): .regular
        case (.accent, _), (.record, _), (.destructive, _): .medium
        }
    }

    private var shadowOpacity: Double {
        switch (kind, size) {
        case (.record, .large): 0.15
        case (.secondary, .large): 0.08
        case (.secondary, _): 0.06
        case (.accent, _), (.record, _), (.destructive, _): 0
        }
    }

    /// Mirrors the design's hover `brightness(1.06)` and pressed `brightness(0.92)` filters on filled buttons.
    private var brightnessAdjustment: Double {
        guard isEnabled else {
            return 0
        }
        if configuration.isPressed {
            return kind == .secondary ? -0.05 : -0.08
        }
        return isHovered && kind != .secondary ? 0.06 : 0
    }
}

/// Height, type size, corner radius and padding of each button size, as specified by the design.
private struct Metrics {
    let height: CGFloat
    let fontSize: CGFloat
    let cornerRadius: CGFloat
    let leadingPadding: CGFloat
    let trailingPadding: CGFloat

    init(_ size: VerbatimButtonStyle.Size) {
        switch size {
        case .small: (height, fontSize, cornerRadius, leadingPadding, trailingPadding) = (20, 11, 5, 8, 8)
        case .mini: (height, fontSize, cornerRadius, leadingPadding, trailingPadding) = (22, 12, 5, 8, 6)
        case .inline: (height, fontSize, cornerRadius, leadingPadding, trailingPadding) = (22, 12, 5, 10, 10)
        case .compact: (height, fontSize, cornerRadius, leadingPadding, trailingPadding) = (24, 12, 6, 10, 10)
        case .dialog: (height, fontSize, cornerRadius, leadingPadding, trailingPadding) = (24, 13, 6, 12, 12)
        case .medium: (height, fontSize, cornerRadius, leadingPadding, trailingPadding) = (28, 13, 7, 14, 14)
        case .large: (height, fontSize, cornerRadius, leadingPadding, trailingPadding) = (40, 14, 10, 0, 0)
        case .regular: (height, fontSize, cornerRadius, leadingPadding, trailingPadding) = (26, 12, 6, 12, 12)
        }
    }
}
