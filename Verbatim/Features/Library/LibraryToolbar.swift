import SwiftUI

/// The Library's toolbar: the section's title and summary, the sort order, and New Recording.
struct LibraryToolbar: ToolbarContent {
    let viewModel: LibraryViewModel
    let newRecording: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(VerbatimColor.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(VerbatimColor.secondaryText)
            }
            .lineLimit(1)
            .padding(.leading, 8)
            .fixedSize()
            .accessibilityElement(children: .combine)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Sort By", selection: sortOrder) {
                    ForEach(RecordingSortOrder.allCases, id: \.self) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 6) {
                    IconView(.sort, size: 14)
                    Text(viewModel.sortOrder.title)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 8)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.toolbarIcon)
            .help("Sort")
            .accessibilityLabel("Sort")
            .accessibilityValue(viewModel.sortOrder.title)

            Button(action: newRecording) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(VerbatimColor.red)
                        .frame(width: 10, height: 10)
                    Text("New Recording")
                }
                .font(.system(size: 12))
                .foregroundStyle(VerbatimColor.primaryText)
                .padding(.horizontal, 10)
            }
            .buttonStyle(.toolbarIcon)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help("New Recording (⌘⇧R)")
        }
    }

    private var title: String {
        viewModel.isSearching ? String(localized: "Search") : viewModel.title(for: viewModel.filter)
    }

    private var subtitle: String {
        if case .searchResults(let results) = viewModel.content {
            return LibraryFormat.count(results.resultCount, singular: "result", plural: "results")
        }
        if viewModel.isSearching {
            return LibraryFormat.count(viewModel.visibleItems.count, singular: "result", plural: "results")
        }
        if viewModel.content == .empty {
            return String(localized: "No recordings")
        }
        let recordings = LibraryFormat.count(viewModel.visibleItems.count, singular: "recording", plural: "recordings")
        if viewModel.showsProcessingNote {
            let counts = viewModel.processingCounts
            return "\(recordings) · \(counts.transcribing) transcribing, \(counts.indexing) indexing"
        }
        return "\(recordings) · \(LibraryFormat.size(viewModel.storage.usedBytes)) on disk"
    }

    private var sortOrder: Binding<RecordingSortOrder> {
        Binding(get: { viewModel.sortOrder }, set: { viewModel.select(sortOrder: $0) })
    }
}
