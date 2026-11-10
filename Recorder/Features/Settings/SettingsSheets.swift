import SwiftUI

/// Confirms removing a model: states the space freed, that recordings and what was made from them are kept, and what
/// happens to the selection. Escape cancels.
struct RemoveModelSheet<Model: InstallableModel>: View {
    let request: ModelSettingsViewModel<Model>.RemovalRequest
    let cancel: () -> Void
    let remove: () -> Void

    var body: some View {
        SettingsSheetContainer {
            Text("Remove “\(request.model.name)”?")
                .font(.system(size: 13, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            SheetMessage(text: message)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel", action: cancel)
                    .buttonStyle(.verbatim(.secondary, size: .dialog))
                    .keyboardShortcut(.cancelAction)
                Button("Remove Model", action: remove)
                    .buttonStyle(.verbatim(.destructive, size: .dialog))
            }
            .padding(.top, 8)
        }
    }

    private var message: String {
        let kept = String(
            localized: "Recordings, transcripts and summaries are kept, and you can download it again at any time."
        )
        let freed = request.reclaimedBytes.map {
            String(localized: "This frees about \(SettingsFormat.size(bytes: $0)) on this Mac.")
        }
        let selectionNote =
            request.isSelected
            ? String(localized: "It’s your selected model, so none will be selected until you choose another.")
            : nil
        return [freed, kept, selectionNote].compactMap { $0 }.joined(separator: " ")
    }
}

/// Third-party components and their licenses; each row opens the full text.
struct LicensesSheet: View {
    let licenses: [ThirdPartyLicense]
    let done: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsSheetContainer {
            Text("Open-Source Licenses")
                .font(.system(size: 13, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(licenses.enumerated()), id: \.element.id) { index, license in
                    if index > 0 {
                        GroupedDivider(leadingInset: 12)
                    }
                    Button {
                        if let url = license.url {
                            openURL(url)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text(license.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(license.license)
                                .foregroundStyle(VerbatimColor.secondaryText)
                            IconView(.chevronRight, size: 11)
                                .foregroundStyle(VerbatimColor.secondaryText)
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(LicenseRowButtonStyle())
                    .accessibilityHint("Opens the full license text in your browser")
                }
            }
            .background(VerbatimColor.groupBackground, in: RoundedRectangle(cornerRadius: 8))
            .hairlineBorder(cornerRadius: 8)
            HStack {
                Spacer(minLength: 0)
                Button(action: done) {
                    Text("Done")
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.verbatim(.accent, size: .dialog))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .onExitCommand(perform: done)
    }
}

/// The design's 380 pt sheet: 18 pt padding and 10 pt spacing on the window background.
private struct SettingsSheetContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(18)
        .frame(width: 380)
        .foregroundStyle(VerbatimColor.primaryText)
        .focusEffectDisabled()
        .presentationBackground(VerbatimColor.windowBackground)
    }
}

private struct SheetMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .lineSpacing(3)
            .foregroundStyle(VerbatimColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LicenseRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(VerbatimColor.primaryText)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .focusRing(cornerRadius: 4)
    }
}
