import SwiftUI

/// Microphone and System Audio rows of the Ready state, each with a live level meter and an on/off switch.
struct AudioSourcesSection: View {
    @Bindable var viewModel: RecorderViewModel

    var body: some View {
        GroupedSection {
            HStack(spacing: 10) {
                IconTile(icon: viewModel.isMicrophoneEnabled ? .microphone : .microphoneOff, tint: VerbatimColor.orange)
                Text("Microphone")
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                microphonePicker
                SimulatedLevelMeter(
                    isActive: viewModel.isMicrophoneEnabled,
                    seed: 1,
                    accessibilityLabel: "Microphone level"
                )
                Toggle("Microphone", isOn: $viewModel.isMicrophoneEnabled)
                    .toggleStyle(.verbatimSwitch)
            }
            .audioRowLayout()

            GroupedDivider(leadingInset: 44)

            HStack(spacing: 10) {
                IconTile(icon: .volume, tint: VerbatimColor.pink)
                Text("System Audio")
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(viewModel.isSystemAudioEnabled ? "All apps" : "Off")
                    .font(.system(size: 12))
                    .foregroundStyle(VerbatimColor.secondaryText)
                SimulatedLevelMeter(
                    isActive: viewModel.isSystemAudioEnabled,
                    seed: 4,
                    accessibilityLabel: "System audio activity"
                )
                Toggle("System audio", isOn: $viewModel.isSystemAudioEnabled)
                    .toggleStyle(.verbatimSwitch)
            }
            .audioRowLayout()
        }
    }

    private var microphonePicker: some View {
        Menu {
            Picker("Input device", selection: $viewModel.selectedMicrophone) {
                ForEach(viewModel.sources.microphones, id: \.self) { microphone in
                    Text(microphone).tag(microphone)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Text(viewModel.selectedMicrophone)
                IconView(.chevronDown, size: 10)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.verbatim(.secondary, size: .mini))
        .fixedSize()
        .opacity(viewModel.isMicrophoneEnabled ? 1 : 0.4)
        .accessibilityLabel("Input device")
        .accessibilityValue(viewModel.selectedMicrophone)
    }
}

extension View {
    /// The 40 pt audio source row used in both the Ready and Recording states.
    func audioRowLayout() -> some View {
        frame(height: 40)
            .padding(.horizontal, 12)
    }
}
