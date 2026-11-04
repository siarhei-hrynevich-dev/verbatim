import SwiftUI

/// Shown on first launch, or after every recording is removed.
struct LibraryEmptyState: View {
    let folderPath: String
    let startRecording: () -> Void
    let addExistingFiles: () -> Void

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

                Button("Add Existing Files…", action: addExistingFiles)
                    .buttonStyle(.verbatim(.secondary, size: .medium))
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
