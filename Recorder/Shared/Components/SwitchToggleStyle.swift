import SwiftUI

/// The design's 32 × 18 pt accent switch.
///
/// Only the switch is drawn; the toggle's label is used for accessibility, so rows can place their visible
/// title and other controls freely. VoiceOver still reports a standard switch with the label and state.
struct SwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                configuration.isOn.toggle()
            }
        } label: {
            SwitchTrack(isOn: configuration.isOn)
        }
        .buttonStyle(SwitchButtonStyle())
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
            .toggleStyle(.switch)
        }
    }
}

extension ToggleStyle where Self == SwitchToggleStyle {
    static var verbatimSwitch: SwitchToggleStyle {
        SwitchToggleStyle()
    }
}

private struct SwitchTrack: View {
    let isOn: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Capsule()
            .fill(isOn ? VerbatimColor.accent : VerbatimColor.switchOff)
            .frame(width: 32, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .padding(2)
            }
            .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct SwitchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Capsule())
            .focusRing(cornerRadius: 9)
    }
}
