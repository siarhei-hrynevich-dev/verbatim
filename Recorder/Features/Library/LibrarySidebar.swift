import SwiftUI

/// Library sections with their recording counts, and the recordings folder and Settings at the bottom.
struct LibrarySidebar: View {
    let viewModel: LibraryViewModel
    let openRecordingsFolder: () -> Void
    let openSettings: () -> Void

    var body: some View {
        List(selection: filterSelection) {
            Section("Library") {
                ForEach([LibraryFilter.all, .recent, .processing], id: \.self, content: row)
            }
            Section("Type") {
                ForEach([LibraryFilter.screen, .audio], id: \.self, content: row)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(VerbatimColor.sidebarBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .accessibilityLabel("Library sections")
    }

    private func row(_ filter: LibraryFilter) -> some View {
        Label {
            Text(filter.title)
                .font(.system(size: 13))
        } icon: {
            IconView(filter.icon, size: 15)
                .foregroundStyle(VerbatimColor.accent)
        }
        .badge(viewModel.count(for: filter))
        .tag(filter)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button(action: openRecordingsFolder) {
                HStack(alignment: .top, spacing: 8) {
                    IconView(.folder, size: 15)
                        .foregroundStyle(VerbatimColor.accent)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Recordings Folder")
                            .font(.system(size: 13))
                        Text(storageSummary)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .allowsTightening(true)
                            .minimumScaleFactor(0.9)
                            .truncationMode(.middle)
                            .foregroundStyle(VerbatimColor.secondaryText)
                    }
                }
                .padding(.vertical, 6)
            }
            .help("Open in Finder")

            Button(action: openSettings) {
                HStack(spacing: 8) {
                    IconView(.gear, size: 15)
                        .foregroundStyle(VerbatimColor.secondaryText)
                    Text("Settings")
                        .font(.system(size: 13))
                }
                .frame(height: 28)
            }
        }
        .buttonStyle(SidebarButtonStyle())
        .padding(10)
        .background(VerbatimColor.sidebarBackground)
    }

    private var storageSummary: String {
        "\(viewModel.storage.folderPath) · \(LibraryFormat.size(viewModel.storage.freeBytes)) free"
    }

    private var filterSelection: Binding<LibraryFilter?> {
        Binding(
            get: { viewModel.filter },
            set: { filter in
                if let filter {
                    viewModel.select(filter: filter)
                }
            }
        )
    }
}

/// A full-width sidebar row button with a fill on hover.
private struct SidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SidebarButtonBody(configuration: configuration)
    }
}

private struct SidebarButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(VerbatimColor.primaryText)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered || configuration.isPressed ? VerbatimColor.fill : .clear, in: shape)
            .contentShape(shape)
            .focusRing(cornerRadius: 6)
            .onHover { isHovered = $0 }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 6)
    }
}
