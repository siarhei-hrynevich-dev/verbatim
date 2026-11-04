import SwiftUI

/// A rounded settings group: rows stacked on the group background with a hairline outline.
struct GroupedSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .groupedBackground()
    }
}

/// A 0.5 pt row separator inset from the leading edge of a grouped section.
struct GroupedDivider: View {
    let leadingInset: CGFloat

    var body: some View {
        VerbatimColor.separator
            .frame(height: 0.5)
            .padding(.leading, leadingInset)
    }
}

extension View {
    /// Applies the grouped-content surface: group background, 10 pt corners and a hairline outline.
    func groupedBackground() -> some View {
        background(VerbatimColor.groupBackground, in: RoundedRectangle(cornerRadius: 10))
            .hairlineBorder(cornerRadius: 10)
    }
}
