import SwiftUI

/// Confirms removing a speech model: states the space freed and that transcripts are kept. Escape cancels.
struct RemoveModelSheet: View {
    let model: SpeechModel
    let cancel: () -> Void
    let remove: () -> Void

    var body: some View {
        SettingsSheetContainer {
            Text("Remove “\(model.name)”?")
                .font(.system(size: 13, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            SheetMessage(
                text: String(
                    localized: """
                        This frees \(SettingsFormat.size(megabytes: model.sizeMegabytes)) on this Mac. Transcripts \
                        already made with this model are kept, and you can download it again at any time.
                        """
                )
            )
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
}

/// Shown after choosing a new folder: new recordings go there, and existing ones move only on request.
struct MoveRecordingsSheet: View {
    let destination: StorageLocation
    let current: StorageLocation
    let recordingCount: Int
    let recordingsMegabytes: Int
    let cancel: () -> Void
    let keepRecordings: () -> Void
    let moveRecordings: () -> Void

    var body: some View {
        SettingsSheetContainer {
            HStack(spacing: 10) {
                IconView(.folder, size: 22)
                    .foregroundStyle(VerbatimColor.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Save new recordings to “\(destination.folderName)” on \(destination.volumeName)?")
                        .font(.system(size: 13, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: "\(destination.path) · \(SettingsFormat.freeSpace(destination.freeBytes)) free")
                        .font(.system(size: 11))
                        .foregroundStyle(VerbatimColor.secondaryText)
                }
            }
            SheetMessage(text: message)
            HStack(spacing: 8) {
                Button("Cancel", action: cancel)
                    .buttonStyle(.verbatim(.secondary, size: .dialog))
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                Button("Don’t Move", action: keepRecordings)
                    .buttonStyle(.verbatim(.secondary, size: .dialog))
                Button("Move Recordings", action: moveRecordings)
                    .buttonStyle(.verbatim(.accent, size: .dialog))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
    }

    private var message: String {
        let size = SettingsFormat.size(megabytes: recordingsMegabytes)
        return String(
            localized: """
                You can also move your \(recordingCount) existing recordings (\(size)). They’re copied first and \
                removed from \(current.path) only after every file is verified. If you don’t move them, they stay \
                where they are and remain in the Library.
                """
        )
    }
}

/// Third-party components and their licenses; each row opens the full text.
struct LicensesSheet: View {
    let licenses: [ThirdPartyLicense]
    let openLicense: (ThirdPartyLicense) -> Void
    let done: () -> Void

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
                        openLicense(license)
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
                    .accessibilityHint("Shows the full license text")
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
