import SwiftUI

/// An attention callout that names a problem and offers a fix plus a fallback action.
struct CalloutBanner: View {
    struct Action {
        let title: LocalizedStringKey
        let perform: () -> Void
    }

    let icon: VerbatimIcon
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let primaryAction: Action
    let secondaryAction: Action
    var tint: Color = VerbatimColor.orange

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(icon: icon, tint: tint, size: .large)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VerbatimColor.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.system(size: 12))
                    .lineSpacing(1.5)
                    .foregroundStyle(VerbatimColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(primaryAction.title, action: primaryAction.perform)
                        .buttonStyle(.verbatim(.accent, size: .compact))
                    Button(secondaryAction.title, action: secondaryAction.perform)
                        .buttonStyle(.verbatim(.secondary, size: .compact))
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .groupedBackground()
        .accessibilityElement(children: .contain)
    }
}
