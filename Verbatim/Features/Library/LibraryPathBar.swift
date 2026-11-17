import SwiftUI

/// Shows where the selected recording lives on disk, with Finder actions. A missing folder says so and offers
/// Locate… and Remove from Library instead.
struct LibraryPathBar: View {
    let item: LibraryItem
    let storage: LibraryStorage
    let showInFinder: () -> Void
    let openFolder: () -> Void
    let locate: () -> Void
    let removeFromLibrary: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            IconView(.folder, size: 13)
                .foregroundStyle(VerbatimColor.accent)
            Text(verbatim: "\(item.location?.parentFolderName ?? storage.folderName) ›")
                .foregroundStyle(VerbatimColor.secondaryText)
                .fixedSize()
            Text(item.folderName)
                .fontWeight(.medium)
                .lineLimit(1)
                .layoutPriority(1)
            Text(detail)
                .foregroundStyle(VerbatimColor.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isMissing {
                Button("Locate…", action: locate)
                    .buttonStyle(.verbatim(.secondary, size: .small))
                Button("Remove from Library", action: removeFromLibrary)
                    .buttonStyle(.verbatim(.secondary, size: .small))
            } else {
                Button("Show in Finder", action: showInFinder)
                    .buttonStyle(.verbatim(.secondary, size: .small))
                Button("Open Folder", action: openFolder)
                    .buttonStyle(.verbatim(.secondary, size: .small))
            }
        }
        .font(.system(size: 11))
        .padding(.leading, 20)
        .padding(.trailing, 10)
        .frame(height: 30)
        .background(VerbatimColor.windowBackground)
        .overlay(alignment: .top) {
            VerbatimColor.separator.frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording folder")
    }

    private var isMissing: Bool {
        item.isMissing
    }

    private var detail: String {
        switch item.location?.unavailability {
        case .volumeUnavailable:
            return String(localized: "— the drive holding this recording isn’t connected.")
        case .accessDenied:
            return String(localized: "— Verbatim doesn’t have access to this file. Locate it to grant access.")
        case .missing:
            return String(localized: "— file not found. It may have been moved or deleted in Finder.")
        case .available, nil:
            break
        }
        if isMissing {
            return String(localized: "— folder not found. It may have been moved or deleted in Finder.")
        }
        return "· \(LibraryFormat.fileSummary(item.fileNames))"
    }
}

/// Explains the processing queue above the Processing list.
struct LibraryProcessingNote: View {
    let pauseAll: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            IconView(.drive, size: 14)
                .foregroundStyle(VerbatimColor.accent)
            Text(
                """
                Transcription and indexing run on this Mac, one recording at a time. Processing pauses while you \
                record.
                """
            )
            .foregroundStyle(VerbatimColor.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Pause All", action: pauseAll)
                .buttonStyle(.verbatim(.secondary, size: .inline))
        }
        .font(.system(size: 12))
        .padding(.vertical, 8)
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) {
            VerbatimColor.separator.frame(height: 0.5)
        }
    }
}

/// Confirms a removal from the Library and offers Undo; Edit › Undo (⌘Z) does the same.
struct LibraryUndoToast: View {
    let title: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
            Button("Undo", action: undo)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Self.actionColor)
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 10)
                .fill(Self.background)
        }
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
        .accessibilityElement(children: .contain)
        .onAppear {
            AccessibilityNotification.Announcement(message).post()
        }
    }

    private var message: String {
        String(localized: "Removed “\(title)” from Library. Files remain in Finder.")
    }

    /// The toast is dark in both appearances.
    private static let background = Color(red: 40 / 255, green: 40 / 255, blue: 42 / 255).opacity(0.88)
    private static let actionColor = Color(red: 100 / 255, green: 210 / 255, blue: 1)
}
