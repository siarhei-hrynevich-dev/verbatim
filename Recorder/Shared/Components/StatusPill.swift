import SwiftUI

/// A small capsule with a colored status dot and a short word, such as “Ready” or “Recording”.
struct StatusPill: View {
    let title: LocalizedStringKey
    let dotColor: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(title)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(VerbatimColor.secondaryText)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(VerbatimColor.fill, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
