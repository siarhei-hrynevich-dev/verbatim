import SwiftUI

/// One recording in the Library list: thumbnail, name, date, duration, size, status and a More button.
///
/// Status is an icon plus a word; failed, untranscribed and missing recordings carry their fix inline. Click
/// selects, double-click opens, and a secondary click or the More button shows the actions menu. VoiceOver reads
/// the row as one element and offers the same actions.
struct LibraryRecordingRow: View {
    let item: LibraryItem
    let isSelected: Bool
    let showsFocusRing: Bool
    let select: () -> Void
    let open: () -> Void
    let showActions: () -> Void
    let requestDeletion: () -> Void
    let performStatusAction: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: LibraryColumn.spacing) {
            RecordingThumbnail(kind: item.kind).libraryColumn(.thumbnail)
            name.libraryColumn(.name)
            secondaryText(LibraryFormat.recordedDate(item.recordedAt)).libraryColumn(.date)
            secondaryText(LibraryFormat.duration(item.duration)).monospacedDigit().libraryColumn(.duration)
            secondaryText(LibraryFormat.size(item.sizeBytes)).monospacedDigit().libraryColumn(.size)
            RecordingStatusView(item: item, performAction: performStatusAction).libraryColumn(.status)
            moreButton.libraryColumn(.actions)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 44)
        .background(background, in: RoundedRectangle(cornerRadius: 6))
        .focusRing(cornerRadius: 6, isVisible: showsFocusRing)
        .opacity(item.status == .missing ? 0.7 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(count: 2, perform: open)
        .simultaneousGesture(TapGesture().onEnded(select))
        .overlay { SecondaryClickArea(action: showActions) }
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(.default, open)
        .accessibilityAction(.showMenu, showActions)
        .accessibilityActions {
            if let title = item.status.actionTitle {
                Button(title, action: performStatusAction)
            }
            Button("Delete Recording…", action: requestDeletion)
        }
    }

    private var name: some View {
        HStack(spacing: 6) {
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            if item.hasTranscript {
                IconView(.file, size: 12)
                    .foregroundStyle(VerbatimColor.tertiaryText)
                    .help("Transcript available")
            }
        }
    }

    private func secondaryText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(VerbatimColor.secondaryText)
            .lineLimit(1)
    }

    private var moreButton: some View {
        Button(action: showActions) {
            IconView(.more, size: 15)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(RowIconButtonStyle())
        .help("More actions")
        .accessibilityLabel("More actions")
    }

    private var background: Color {
        if isSelected {
            return VerbatimColor.accent.opacity(0.16)
        }
        return isHovered ? VerbatimColor.fill : .clear
    }

    private var accessibilityLabel: String {
        var parts = [
            item.title,
            LibraryFormat.recordedDate(item.recordedAt),
            Duration.seconds(item.duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)),
            LibraryFormat.size(item.sizeBytes),
            item.status.label
        ]
        if item.hasTranscript {
            parts.append(String(localized: "Transcript available"))
        }
        return parts.joined(separator: ", ")
    }
}

/// The status column: icon and word, an inline fix when there is one, and a progress bar while processing.
private struct RecordingStatusView: View {
    let item: LibraryItem
    let performAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                IconView(item.status.icon, size: 13)
                    .foregroundStyle(item.status.iconColor)
                Text(item.status.label)
                    .foregroundStyle(item.status.labelColor)
                    .lineLimit(1)
                if let actionTitle = item.status.actionTitle {
                    Button(actionTitle, action: performAction)
                        .buttonStyle(.verbatim(.secondary, size: .small))
                        .fixedSize()
                        .padding(.leading, 2)
                }
            }
            .font(.system(size: 12))

            if let progress = item.processingProgress {
                ProgressBar(fraction: progress)
            }
        }
    }
}

/// A thin accent progress bar, 140 pt wide.
private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        Capsule()
            .fill(VerbatimColor.fill)
            .frame(width: 140, height: 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(VerbatimColor.accent)
                    .frame(width: 140 * min(max(fraction, 0), 1))
            }
            .accessibilityHidden(true)
    }
}

/// A 52 × 32 pt preview: a stylized screen for screen recordings, a waveform glyph for audio.
struct RecordingThumbnail: View {
    let kind: LibraryItem.Kind

    var body: some View {
        Group {
            switch kind {
            case .screen:
                ZStack(alignment: .topLeading) {
                    VerbatimColor.thumbnail
                    VerbatimColor.thumbnailBar
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(VerbatimColor.thumbnailWindow)
                        .frame(width: 24, height: 17)
                        .offset(x: 6, y: 8)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(VerbatimColor.thumbnailWindowAlternate)
                        .frame(width: 22, height: 15)
                        .offset(x: 24, y: 12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .hairlineBorder(cornerRadius: 5)
            case .audio:
                RoundedRectangle(cornerRadius: 5)
                    .fill(VerbatimColor.fill)
                    .overlay {
                        IconView(.audio, size: 16)
                            .foregroundStyle(VerbatimColor.accent)
                    }
            }
        }
        .frame(width: 52, height: 32)
        .accessibilityHidden(true)
    }
}

/// The row's 24 pt More button: secondary icon with a fill on hover.
private struct RowIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowIconButtonBody(configuration: configuration)
    }
}

private struct RowIconButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(VerbatimColor.secondaryText)
            .background(isHovered || configuration.isPressed ? VerbatimColor.fill : .clear, in: shape)
            .contentShape(shape)
            .focusRing(cornerRadius: 5)
            .onHover { isHovered = $0 }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 5)
    }
}

extension LibraryItem.Status {
    var label: String {
        switch self {
        case .ready: String(localized: "Ready")
        case .transcribing(let progress): String(localized: "Transcribing \(Self.percent(progress))%")
        case .indexing(let progress): String(localized: "Indexing \(Self.percent(progress))%")
        case .recorded: String(localized: "Recorded")
        case .failed: String(localized: "Failed")
        case .missing: String(localized: "File missing")
        }
    }

    var icon: VerbatimIcon {
        switch self {
        case .ready: .check
        case .transcribing, .indexing: .loader
        case .recorded: .clock
        case .failed: .alert
        case .missing: .missingFile
        }
    }

    var iconColor: Color {
        switch self {
        case .ready: VerbatimColor.green
        case .transcribing, .indexing: VerbatimColor.accent
        case .recorded: VerbatimColor.secondaryText
        case .failed, .missing: VerbatimColor.red
        }
    }

    var labelColor: Color {
        switch self {
        case .ready, .recorded: VerbatimColor.secondaryText
        case .transcribing, .indexing: VerbatimColor.primaryText
        case .failed, .missing: VerbatimColor.red
        }
    }

    /// The fix offered inline for this status, if any.
    var actionTitle: String? {
        switch self {
        case .recorded: String(localized: "Transcribe")
        case .failed: String(localized: "Retry")
        case .missing: String(localized: "Locate…")
        case .ready, .transcribing, .indexing: nil
        }
    }

    private static func percent(_ fraction: Double) -> Int {
        Int((fraction * 100).rounded())
    }
}
