import AppKit
import SwiftUI

/// Builds the Dock menu and the menu bar item's menu from the Recorder state, as in design section “04 Dock”.
///
/// New Recording opens the Recorder with its saved settings; it never starts capture by itself. While recording,
/// the first Dock menu line is the live timer and Stop Recording becomes the bold default action.
@MainActor
enum RecordingMenus {
    static func dockMenu(recorder: RecorderViewModel, navigator: WindowNavigator) -> NSMenu {
        let menu = NSMenu()
        if let clock = recorder.activeClock {
            menu.addItem(dockTimerItem(clock: clock))
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem("Open Recorder", action: navigator.showRecorder))
            menu.addItem(ActionMenuItem("Stop Recording", isDefault: true, action: recorder.stopRecording))
            menu.addItem(ActionMenuItem("Recordings Library", action: navigator.showLibrary))
        } else {
            menu.addItem(ActionMenuItem("New Recording", isDefault: true, action: navigator.showRecorder))
            menu.addItem(ActionMenuItem("Open Recorder", action: navigator.showRecorder))
            menu.addItem(ActionMenuItem("Recordings Library", action: navigator.showLibrary))
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem("Settings…", action: navigator.showSettings))
        }
        return menu
    }

    /// The menu bar item's menu: what is being recorded, Pause and Stop, then the windows.
    static func statusMenu(recorder: RecorderViewModel, navigator: WindowNavigator) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(statusHeaderItem(recorder: recorder))
        menu.addItem(.separator())
        let isPaused = recorder.activeClock?.isPaused ?? false
        menu.addItem(
            ActionMenuItem(
                isPaused ? "Resume Recording" : "Pause Recording",
                keyEquivalent: "p",
                modifiers: [.option, .command],
                action: { recorder.togglePause() }
            )
        )
        menu.addItem(
            ActionMenuItem(
                "Stop Recording",
                keyEquivalent: "r",
                modifiers: [.shift, .command],
                isDefault: true,
                action: recorder.stopRecording
            )
        )
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Open Recorder", action: navigator.showRecorder))
        menu.addItem(ActionMenuItem("Recordings Library", action: navigator.showLibrary))
        return menu
    }

    private static func dockTimerItem(clock: RecordingClock) -> NSMenuItem {
        let timer = RecordingClock.timerText(for: clock.elapsed(at: .now))
        let title = NSMutableAttributedString(
            string: "● ",
            attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.menuFont(ofSize: 0)]
        )
        title.append(
            NSAttributedString(
                string: String(localized: "Recording — \(timer)"),
                attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: menuFont(monospacedDigits: true)]
            )
        )
        let item = NSMenuItem(title: title.string, action: nil, keyEquivalent: "")
        item.attributedTitle = title
        item.isEnabled = false
        return item
    }

    private static func statusHeaderItem(recorder: RecorderViewModel) -> NSMenuItem {
        let header = RecordingMenuHeader(title: recorder.menuTitle, detail: recorder.menuDetail)
        let hostingView = NSHostingView(rootView: header)
        hostingView.frame.size = hostingView.fittingSize
        let item = NSMenuItem()
        item.view = hostingView
        item.isEnabled = false
        return item
    }

    fileprivate static func menuFont(monospacedDigits: Bool = false, bold: Bool = false) -> NSFont {
        let size = NSFont.menuFont(ofSize: 0).pointSize
        let weight: NSFont.Weight = bold ? .semibold : .regular
        return monospacedDigits
            ? .monospacedDigitSystemFont(ofSize: size, weight: weight)
            : .systemFont(ofSize: size, weight: weight)
    }
}

/// The menu bar menu's first line: what is recorded, and which audio sources are on.
private struct RecordingMenuHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 14)
        .frame(width: 250, alignment: .leading)
    }
}

/// A menu item that runs a closure, for menus built in code.
@MainActor
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    /// `isDefault` shows the item in bold, marking the action a click on the owning control would take.
    init(
        _ title: String,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [],
        isDefault: Bool = false,
        action: @escaping () -> Void
    ) {
        handler = action
        super.init(title: title, action: #selector(runHandler), keyEquivalent: keyEquivalent)
        target = self
        keyEquivalentModifierMask = modifiers
        if isDefault {
            attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: RecordingMenus.menuFont(bold: true)]
            )
        }
    }

    // Menus here are built in code only; AppKit requires the initializer but never decodes these items.
    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("ActionMenuItem is not decodable")
    }

    @objc private func runHandler() {
        handler()
    }
}

extension RecorderViewModel {
    /// The clock of the running or paused recording, if any.
    var activeClock: RecordingClock? {
        if case .recording(let clock) = phase {
            return clock
        }
        return nil
    }

    /// `Recording · Built-in Display`, or `Paused · …`.
    var menuTitle: String {
        let state = activeClock?.isPaused == true ? String(localized: "Paused") : String(localized: "Recording")
        return "\(state) · \(activeSourceName)"
    }

    /// `Microphone on · System audio on`.
    var menuDetail: String {
        let microphone = isMicrophoneActive ? String(localized: "Microphone on") : String(localized: "Microphone off")
        let systemAudio =
            isSystemAudioActive ? String(localized: "System audio on") : String(localized: "System audio off")
        return "\(microphone) · \(systemAudio)"
    }
}
