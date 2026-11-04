import SwiftUI

/// The design's segmented control: a tinted track with a raised, bold selected segment.
///
/// `.regular` stretches equal-width segments across the available width (26 pt tall);
/// `.small` sizes segments to their titles (20 pt tall), as used in inline setting rows.
/// Each segment is a focusable button announced as selected or not, inside a labelled group.
struct SegmentedControl<Value: Hashable>: View {
    struct Segment {
        let value: Value
        let title: LocalizedStringKey
        var icon: VerbatimIcon?
    }

    enum Size {
        case regular
        case small
    }

    let accessibilityLabel: LocalizedStringKey
    let segments: [Segment]
    @Binding var selection: Value
    var size: Size = .regular

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments, id: \.value) { segment in
                segmentButton(segment)
            }
        }
        .padding(trackPadding)
        .background(VerbatimColor.fill, in: RoundedRectangle(cornerRadius: trackCornerRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func segmentButton(_ segment: Segment) -> some View {
        let isSelected = segment.value == selection
        return Button {
            selection = segment.value
        } label: {
            HStack(spacing: 6) {
                if let icon = segment.icon {
                    IconView(icon, size: 13)
                }
                Text(segment.title)
            }
            .font(.system(size: fontSize, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(VerbatimColor.primaryText)
            .padding(.horizontal, size == .small ? 10 : 0)
            .frame(maxWidth: size == .regular ? .infinity : nil)
            .frame(height: segmentHeight)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: segmentCornerRadius)
                        .fill(VerbatimColor.selectedSegment)
                        .hairlineBorder(cornerRadius: segmentCornerRadius)
                        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: segmentCornerRadius))
        }
        .buttonStyle(SegmentButtonStyle(cornerRadius: segmentCornerRadius))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fontSize: CGFloat { size == .regular ? 12 : 11 }
    private var segmentHeight: CGFloat { size == .regular ? 26 : 20 }
    private var segmentCornerRadius: CGFloat { size == .regular ? 6 : 5 }
    private var trackPadding: CGFloat { size == .regular ? 2 : 1 }
    private var trackCornerRadius: CGFloat { size == .regular ? 8 : 6 }
}

private struct SegmentButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .focusRing(cornerRadius: cornerRadius)
    }
}
