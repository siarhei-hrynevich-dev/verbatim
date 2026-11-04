import SwiftUI

/// Search results: matching titles, then transcript moments grouped by recording. Each moment opens the
/// recording at its timestamp.
struct LibrarySearchResultsView: View {
    let results: LibrarySearchResults
    let query: String
    /// Opens a recording, at a transcript position in seconds when one is given.
    let openRecording: (LibraryItem.ID, TimeInterval?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !results.titleMatches.isEmpty {
                    titleSection
                }
                transcriptSection
                Text("“Related” moments match the meaning of your search, not the exact words.")
                    .font(.system(size: 12))
                    .foregroundStyle(VerbatimColor.secondaryText)
                    .padding(.leading, 4)
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Titles · \(results.titleMatches.count)")
            VStack(spacing: 0) {
                ForEach(results.titleMatches) { item in
                    Button {
                        openRecording(item.id, nil)
                    } label: {
                        HStack(spacing: 12) {
                            ResultThumbnail(kind: item.kind)
                            Text(item.title)
                                .font(.system(size: 13, weight: .medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(dateAndDuration(of: item))
                                .font(.system(size: 12))
                                .foregroundStyle(VerbatimColor.secondaryText)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(ResultRowButtonStyle())
                }
            }
            .resultGroupBackground()
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading(transcriptHeading)
            VStack(spacing: 10) {
                ForEach(results.momentGroups) { group in
                    momentGroup(group)
                }
            }
        }
    }

    private func momentGroup(_ group: LibrarySearchResults.MomentGroup) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ResultThumbnail(kind: group.item.kind)
                Text(group.item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(dateAndDuration(of: group.item))
                    .font(.system(size: 12))
                    .foregroundStyle(VerbatimColor.secondaryText)
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            ForEach(group.moments) { moment in
                GroupedDivider(leadingInset: 62)
                MomentRow(moment: moment, query: query) {
                    openRecording(group.item.id, moment.timestamp)
                }
            }
        }
        .resultGroupBackground()
        .accessibilityElement(children: .contain)
    }

    private func sectionHeading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(VerbatimColor.secondaryText)
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private var transcriptHeading: String {
        let moments = LibraryFormat.count(results.momentCount, singular: "moment", plural: "moments")
        let recordings = LibraryFormat.count(
            results.momentGroups.count,
            singular: "recording",
            plural: "recordings"
        )
        return String(localized: "In transcripts · \(moments) in \(recordings)")
    }

    private func dateAndDuration(of item: LibraryItem) -> String {
        "\(LibraryFormat.recordedDate(item.recordedAt)) · \(LibraryFormat.duration(item.duration))"
    }
}

/// One matching transcript line: timestamp, speaker, the line with the query highlighted, and the match kind.
private struct MomentRow: View {
    let moment: LibrarySearchResults.Moment
    let query: String
    let open: () -> Void

    var body: some View {
        let timestamp = LibraryFormat.timestamp(moment.timestamp)
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                HStack(spacing: 5) {
                    IconView(.play, size: 9)
                    Text(timestamp)
                }
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(VerbatimColor.accent)
                .frame(width: 70, alignment: .leading)

                Text(moment.speaker)
                    .font(.system(size: 12))
                    .foregroundStyle(VerbatimColor.secondaryText)
                    .frame(width: 90, alignment: .leading)

                Text(highlightedText)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(moment.match == .exact ? "Exact" : "Related")
                    .font(.system(size: 11))
                    .foregroundStyle(VerbatimColor.secondaryText)
                    .padding(.vertical, 1)
                    .padding(.horizontal, 8)
                    .background(VerbatimColor.fill, in: Capsule())
            }
            .padding(.vertical, 8)
            .padding(.leading, 62)
            .padding(.trailing, 12)
        }
        .buttonStyle(ResultRowButtonStyle())
        .help("Open at \(timestamp)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(timestamp), \(moment.speaker): \(moment.text). \(moment.match == .exact ? "Exact" : "Related") match"
        )
        .accessibilityHint("Opens the recording at \(timestamp)")
    }

    /// Marks every occurrence of the whole query, ignoring case.
    private var highlightedText: AttributedString {
        var text = AttributedString(moment.text)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return text
        }
        var searchStart = text.startIndex
        while let range = text[searchStart...].range(of: needle, options: .caseInsensitive) {
            text[range].backgroundColor = Self.highlight
            searchStart = range.upperBound
        }
        return text
    }

    /// The design's match highlight, the same in both appearances.
    private static let highlight = Color(red: 1, green: 214 / 255, blue: 10 / 255).opacity(0.55)
}

/// A 40 × 25 pt block standing in for the recording's preview.
private struct ResultThumbnail: View {
    let kind: LibraryItem.Kind

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(kind == .audio ? VerbatimColor.fill : VerbatimColor.thumbnail)
            .frame(width: 40, height: 25)
            .accessibilityHidden(true)
    }
}

/// A full-width result row with a fill on hover.
private struct ResultRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ResultRowBody(configuration: configuration)
    }
}

private struct ResultRowBody: View {
    let configuration: ButtonStyleConfiguration

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(VerbatimColor.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered || configuration.isPressed ? VerbatimColor.fill : .clear)
            .contentShape(Rectangle())
            .focusRing(cornerRadius: 0)
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// A grouped surface whose row hover fills are clipped to its rounded corners.
    fileprivate func resultGroupBackground() -> some View {
        clipShape(RoundedRectangle(cornerRadius: 10))
            .groupedBackground()
    }
}
