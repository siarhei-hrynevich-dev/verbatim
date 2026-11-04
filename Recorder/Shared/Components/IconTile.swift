import SwiftUI

/// A white icon on a rounded colored square, used for row and callout leading icons.
struct IconTile: View {
    enum Size {
        /// 22 pt tile with a 13 pt icon, for list rows.
        case small
        /// 28 pt tile with a 15 pt icon, for callouts.
        case large
    }

    let icon: VerbatimIcon
    let tint: Color
    var size: Size = .small

    var body: some View {
        RoundedRectangle(cornerRadius: size == .small ? 6 : 7)
            .fill(tint)
            .frame(width: tileSize, height: tileSize)
            .overlay {
                IconView(icon, size: size == .small ? 13 : 15)
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }

    private var tileSize: CGFloat {
        size == .small ? 22 : 28
    }
}
