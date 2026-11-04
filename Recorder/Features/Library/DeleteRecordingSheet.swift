import SwiftUI

/// Confirms deleting a recording: names its folder and files, moves them to the Trash, and offers the
/// non-destructive Remove from Library in the same place. Escape cancels.
struct DeleteRecordingSheet: View {
    let item: LibraryItem
    let storage: LibraryStorage
    let removeFromLibrary: () -> Void
    let cancel: () -> Void
    let moveToTrash: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(VerbatimColor.fill)
                    .frame(width: 44, height: 44)
                    .overlay {
                        IconView(.trash, size: 24)
                            .foregroundStyle(VerbatimColor.red)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Delete “\(item.title)”?")
                        .font(.system(size: 13, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .foregroundStyle(VerbatimColor.secondaryText)
                    folderSummary
                        .padding(.top, 2)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Remove from Library Only", action: removeFromLibrary)
                    .buttonStyle(.verbatim(.secondary, size: .dialog))
                Spacer(minLength: 0)
                Button("Cancel", action: cancel)
                    .buttonStyle(.verbatim(.secondary, size: .dialog))
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash", action: moveToTrash)
                    .buttonStyle(.verbatim(.destructive, size: .dialog))
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 440)
        .foregroundStyle(VerbatimColor.primaryText)
        .focusEffectDisabled()
        .presentationBackground(VerbatimColor.windowBackground)
    }

    private var message: String {
        let size = LibraryFormat.size(item.sizeBytes)
        return String(
            localized: """
                The recording folder and its \(item.fileNames.count) files (\(size)) will be moved to the Trash. \
                You can restore them from the Trash in Finder until it’s emptied.
                """
        )
    }

    private var folderSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(storage.folderPath)/\(item.folderName)")
                .fontWeight(.medium)
            Text(LibraryFormat.fileSummary(item.fileNames))
                .foregroundStyle(VerbatimColor.secondaryText)
        }
        .font(.system(size: 11))
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VerbatimColor.fill, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
    }
}
