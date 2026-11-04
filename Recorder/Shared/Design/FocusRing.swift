import SwiftUI

/// Draws a keyboard focus ring around a custom control.
///
/// Custom Verbatim controls disable the system focus effect and draw this ring instead, so the ring follows
/// each control's corner radius. Apply it inside a style body, where `isFocused` reflects the control's focus.
struct FocusRing: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content.modifier(FocusRingOverlay(cornerRadius: cornerRadius, isVisible: isFocused))
    }
}

/// The focus ring drawing, for views that track focus themselves, such as a list marking its selected row.
private struct FocusRingOverlay: ViewModifier {
    let cornerRadius: CGFloat
    let isVisible: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isVisible {
                RoundedRectangle(cornerRadius: cornerRadius + Self.ringWidth / 2)
                    .stroke(VerbatimColor.accent.opacity(0.5), lineWidth: Self.ringWidth)
                    .padding(-Self.ringWidth / 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private static let ringWidth: CGFloat = 3
}

extension View {
    func focusRing(cornerRadius: CGFloat) -> some View {
        modifier(FocusRing(cornerRadius: cornerRadius))
    }

    /// Draws the focus ring when `isVisible` is true, independent of the view's own focus state.
    func focusRing(cornerRadius: CGFloat, isVisible: Bool) -> some View {
        modifier(FocusRingOverlay(cornerRadius: cornerRadius, isVisible: isVisible))
    }

    /// Adds a 0.5 pt inner hairline, matching the design's `0 0 0 0.5px var(--sep)` outline.
    func hairlineBorder(cornerRadius: CGFloat, color: Color = VerbatimColor.separator) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(color, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }
}
