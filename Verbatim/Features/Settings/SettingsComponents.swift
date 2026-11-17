import SwiftUI

/// A titled settings group with an optional footnote below it.
struct SettingsSection<Content: View>: View {
    var title: LocalizedStringKey?
    var footnote: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 2)
                    .accessibilityAddTraits(.isHeader)
            }
            GroupedSection {
                content
            }
            if let footnote {
                SettingsFootnote(text: footnote)
            }
        }
    }
}

/// Explanatory text under a settings group.
struct SettingsFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .lineSpacing(2)
            .foregroundStyle(VerbatimColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
    }
}

/// A row with a title, an optional description, and trailing controls.
struct SettingsRow<Trailing: View>: View {
    let title: LocalizedStringKey
    var detail: String?
    /// A fixed 36 pt row without vertical padding, for single-line rows with a control.
    var isCompact = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .lineSpacing(1.5)
                        .foregroundStyle(VerbatimColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, isCompact ? 0 : 9)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
    }
}

/// A row with a title, an optional description and a switch. The title labels the switch for VoiceOver.
struct SettingsToggleRow: View {
    let title: LocalizedStringKey
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.verbatimSwitch)
        }
    }
}

/// A pop-up button that shows the selected option and an up-down chevron, as the design's 22 pt menus do.
struct SettingsPopUpMenu<Option: Hashable, Content: View>: View {
    let accessibilityLabel: LocalizedStringKey
    let selectionTitle: String
    @Binding var selection: Option
    @ViewBuilder let options: Content

    var body: some View {
        Menu {
            Picker(accessibilityLabel, selection: $selection) {
                options
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Text(selectionTitle)
                IconView(.upDown, size: 11)
                    .foregroundStyle(VerbatimColor.secondaryText)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.verbatim(.secondary, size: .mini))
        .fixedSize()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selectionTitle)
    }
}

/// A compact status label for a model: icon and word on a tinted or outlined capsule.
struct ModelStatusChip: View {
    enum Style {
        case prominent
        case filled
        case outlined
    }

    let title: String
    let icon: VerbatimIcon
    let iconColor: Color
    var style: Style = .filled

    var body: some View {
        HStack(spacing: 4) {
            IconView(icon, size: 11)
                .foregroundStyle(style == .prominent ? .white : iconColor)
            Text(title)
                .monospacedDigit()
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(style == .prominent ? .white : VerbatimColor.secondaryText)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(background, in: RoundedRectangle(cornerRadius: 5))
        .hairlineBorder(cornerRadius: 5, color: style == .outlined ? VerbatimColor.separator : .clear)
        .accessibilityElement(children: .combine)
    }

    private var background: Color {
        switch style {
        case .prominent: VerbatimColor.accent
        case .filled: VerbatimColor.fill
        case .outlined: .clear
        }
    }
}

/// A 4 pt determinate progress bar that fills the available width.
struct SettingsProgressBar: View {
    let fraction: Double
    var tint: Color = VerbatimColor.accent

    var body: some View {
        Capsule()
            .fill(VerbatimColor.fill)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .accessibilityHidden(true)
    }
}

/// A 4 pt orange bar with a segment sweeping across it, for work without measurable progress.
struct IndeterminateProgressBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(VerbatimColor.fill)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    if reduceMotion {
                        segment(width: proxy.size.width, offset: 0.3)
                    } else {
                        TimelineView(.animation) { context in
                            segment(width: proxy.size.width, offset: Self.offset(at: context.date))
                        }
                    }
                }
            }
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }

    private func segment(width: CGFloat, offset: Double) -> some View {
        Capsule()
            .fill(VerbatimColor.orange)
            .frame(width: width * 0.35)
            .offset(x: width * offset)
    }

    /// Sweeps from just before the leading edge to past the trailing edge every 2.8 seconds.
    private static func offset(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.8) / 2.8
        return phase * 1.4 - 0.35
    }
}

/// A 24 pt icon-only button: secondary icon with a fill on hover.
struct SettingsIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsIconButtonBody(configuration: configuration)
    }
}

private struct SettingsIconButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(VerbatimColor.secondaryText)
            .frame(width: 24, height: 24)
            .background(isHovered && isEnabled ? VerbatimColor.fill : .clear, in: shape)
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.35)
            .focusRing(cornerRadius: 6)
            .onHover { isHovered = $0 }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 6)
    }
}

/// Settings-wide metrics.
enum SettingsLayout {
    static let windowWidth: CGFloat = 620
    static let contentPadding: CGFloat = 20
    /// The AI Models tab scrolls inside a fixed height, as in the design.
    static let modelsTabHeight: CGFloat = 640
}
