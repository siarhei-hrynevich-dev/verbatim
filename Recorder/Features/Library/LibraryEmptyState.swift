import SwiftUI

/// Shown on first launch, or after every recording is removed.
struct LibraryEmptyState: View {
    let folderPath: String
    let startRecording: () -> Void
    /// `nil` hides the button; adding existing files is not implemented for real recordings.
    var addExistingFiles: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            IconView(.record, size: 48)
                .foregroundStyle(VerbatimColor.tertiaryText)
            Text("No Recordings")
                .font(.system(size: 20, weight: .bold))
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            Text(
                """
                Recordings and their transcripts are saved to \(unbreakablePath) on this Mac. Nothing leaves your \
                computer.
                """
            )
            .font(.system(size: 13))
            .lineSpacing(4)
            .foregroundStyle(VerbatimColor.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(action: startRecording) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(.white)
                            .frame(width: 9, height: 9)
                        Text("Start Recording")
                    }
                }
                .buttonStyle(.verbatim(.record, size: .medium))

                if let addExistingFiles {
                    Button("Add Existing Files…", action: addExistingFiles)
                        .buttonStyle(.verbatim(.secondary, size: .medium))
                }
            }
            .padding(.top, 10)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Keeps the path on one line: a word joiner after each slash stops text layout from breaking there.
    private var unbreakablePath: String {
        folderPath.replacingOccurrences(of: "/", with: "/\u{2060}")
    }
}

/// Shown instead of the list when the Library's database cannot be read.
struct LibraryLoadFailedState: View {
    let issue: LibraryIssue
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            IconView(.alert, size: 40)
                .foregroundStyle(VerbatimColor.tertiaryText)
            Text(issue.title)
                .font(.system(size: 17, weight: .bold))
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            Text(issue.message)
                .font(.system(size: 13))
                .foregroundStyle(VerbatimColor.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again", action: retry)
                .buttonStyle(.verbatim(.secondary, size: .medium))
                .padding(.top, 10)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown when a search finds no recordings.
struct LibraryNoResultsState: View {
    let query: String

    var body: some View {
        VStack(spacing: 8) {
            IconView(.search, size: 32)
                .foregroundStyle(VerbatimColor.tertiaryText)
            Text("No Results for “\(query)”")
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
            Text("Search looks at recording titles and dates.")
                .font(.system(size: 12))
                .foregroundStyle(VerbatimColor.secondaryText)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
