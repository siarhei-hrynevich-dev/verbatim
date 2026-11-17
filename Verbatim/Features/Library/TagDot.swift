import SwiftUI

/// A tag's colored circle: solid when the recording has the tag, an outline when it could.
struct TagDot: View {
    let color: TagColor
    var isFilled = true
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(isFilled ? color.swiftUI : .clear)
            .overlay { Circle().strokeBorder(color.swiftUI, lineWidth: 1) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A recording's tags, overlapping like Finder's list view.
struct TagDots: View {
    let tags: [RecordingTag]

    var body: some View {
        HStack(spacing: -3) {
            ForEach(tags) { tag in
                TagDot(color: tag.color)
                    .overlay { Circle().strokeBorder(VerbatimColor.contentBackground, lineWidth: 1) }
            }
        }
        .help(tags.map(\.name).joined(separator: ", "))
    }
}
