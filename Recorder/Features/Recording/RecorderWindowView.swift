import SwiftUI

/// The compact Recorder utility window: a 52 pt toolbar header with status, then setup or live recording content.
struct RecorderWindowView: View {
    @Bindable var viewModel: RecorderViewModel
    let openLibrary: () -> Void
    let openSettings: () -> Void

    var body: some View {
        content
            .frame(width: RecorderLayout.windowWidth)
            .frame(minHeight: RecorderLayout.minimumContentHeight)
            // Fixes the window to the content's ideal height, so it grows only when a state needs more room.
            .fixedSize()
            .foregroundStyle(VerbatimColor.primaryText)
            // Verbatim controls draw focus rings that follow their own shapes.
            .focusEffectDisabled()
            .containerBackground(VerbatimColor.windowBackground, for: .window)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .navigationTitle("Verbatim")
            .toolbar { toolbarContent }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .ready:
            RecorderSetupView(viewModel: viewModel, showLibrary: openLibrary)
        case .recording(let clock):
            ActiveRecordingView(viewModel: viewModel, clock: clock)
        }
    }

    /// Title and status sit beside the traffic lights; Library and Settings sit at the trailing edge.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                Text("Verbatim")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VerbatimColor.primaryText)
                    .accessibilityAddTraits(.isHeader)
                StatusPill(title: viewModel.status.title, dotColor: viewModel.status.dotColor)
            }
            // Keeps the toolbar from truncating the status when it changes length.
            .fixedSize()
        }

        // With the window title hidden, the toolbar has no flexible space; an empty principal item adds it,
        // pushing the following items to the trailing edge.
        ToolbarItem(placement: .principal) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)
        }

        ToolbarItemGroup {
            Button(action: openLibrary) {
                HStack(spacing: 6) {
                    IconView(.list, size: 15)
                    Text("Library")
                }
                .padding(.horizontal, 8)
            }
            .buttonStyle(.toolbarIcon)
            .help("Recordings Library")
            .accessibilityLabel("Recordings Library")

            Button(action: openSettings) {
                IconView(.gear, size: 15)
            }
            .buttonStyle(.toolbarIcon)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
    }
}

/// Fixed metrics of the Recorder window.
enum RecorderLayout {
    static let windowWidth: CGFloat = 480
    /// The design's 590 pt window minus the 52 pt toolbar.
    static let minimumContentHeight: CGFloat = 538
    static let horizontalPadding: CGFloat = 20
    static let contentWidth = windowWidth - 2 * horizontalPadding
    static let sectionSpacing: CGFloat = 14
}

extension RecorderViewModel.Status {
    var title: LocalizedStringKey {
        switch self {
        case .ready: "Ready"
        case .needsAttention: "Needs Attention"
        case .recording: "Recording"
        case .paused: "Paused"
        }
    }

    var dotColor: Color {
        switch self {
        case .ready: VerbatimColor.green
        case .needsAttention, .paused: VerbatimColor.orange
        case .recording: VerbatimColor.red
        }
    }
}

#Preview("Ready") {
    RecorderWindowView(viewModel: RecorderViewModel(scenario: .idle), openLibrary: {}, openSettings: {})
}

#Preview("Window source · dark") {
    RecorderWindowView(viewModel: RecorderViewModel(scenario: .picker), openLibrary: {}, openSettings: {})
        .preferredColorScheme(.dark)
}

#Preview("Recording") {
    RecorderWindowView(viewModel: RecorderViewModel(scenario: .recording), openLibrary: {}, openSettings: {})
}

#Preview("Permission off") {
    RecorderWindowView(viewModel: RecorderViewModel(scenario: .permission), openLibrary: {}, openSettings: {})
}
