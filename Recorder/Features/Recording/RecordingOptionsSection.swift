import SwiftUI

/// Video quality, frame rate and auto-transcription settings. Video options are hidden for Audio Only.
struct RecordingOptionsSection: View {
    @Bindable var viewModel: RecorderViewModel

    var body: some View {
        GroupedSection {
            if viewModel.captureMode.capturesVideo {
                optionRow("Quality") {
                    SegmentedControl(
                        accessibilityLabel: "Quality",
                        segments: VideoQuality.allCases.map { .init(value: $0, title: "\($0.rawValue)") },
                        selection: $viewModel.quality,
                        size: .small
                    )
                }
                GroupedDivider(leadingInset: 12)

                optionRow("Frame Rate") {
                    SegmentedControl(
                        accessibilityLabel: "Frame Rate",
                        segments: FrameRate.allCases.map { .init(value: $0, title: "\($0.rawValue) fps") },
                        selection: $viewModel.frameRate,
                        size: .small
                    )
                }
                GroupedDivider(leadingInset: 12)
            }

            optionRow("Transcribe when recording ends") {
                Toggle("Transcribe when recording ends", isOn: $viewModel.transcribesWhenFinished)
                    .toggleStyle(.verbatimSwitch)
            }
        }
    }

    private func optionRow(_ title: LocalizedStringKey, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            control()
        }
        .frame(height: 36)
        .padding(.horizontal, 12)
    }
}
