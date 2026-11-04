import SwiftUI

/// The toolbar's Export pop-up: copy and export the transcript. Every item is disabled until a transcript exists.
struct ViewerExportMenu: View {
    let hasTranscript: Bool
    let actions: ViewerWindowActions

    var body: some View {
        Menu {
            Button("Copy Selected Text") {}
                .keyboardShortcut("c", modifiers: .command)
                .disabled(true)
            Button("Copy Entire Transcript", action: actions.copyTranscript)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!hasTranscript)
            Divider()
            ForEach(ViewerExportFormat.allCases, id: \.self) { format in
                Button("Export as \(format.rawValue)…") { actions.exportTranscript(format) }
                    .disabled(!hasTranscript)
            }
            Divider()
            Button("Show Transcript in Finder", action: actions.showTranscriptInFinder)
                .disabled(!hasTranscript)
        } label: {
            HStack(spacing: 6) {
                IconView(.export, size: 14)
                Text("Export")
                IconView(.chevronDown, size: 10)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(SegmentPartButtonStyle(edges: .trailing))
        .fixedSize()
        .help("Export Transcript")
        .accessibilityLabel("Export Transcript")
    }
}
