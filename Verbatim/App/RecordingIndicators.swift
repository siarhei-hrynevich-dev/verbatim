import AppKit
import Observation

/// Shows that a recording is running while the Recorder window can stay closed: a menu bar item with a red dot and
/// the elapsed time, and a red badge on the Dock icon, which itself doesn't change.
///
/// Both appear only while recording, and the menu bar item only if the user wants it. The controller observes the
/// Recorder state and owns the one-second task that refreshes the timer; the task ends when recording stops.
@MainActor
final class RecordingIndicators: NSObject, NSMenuDelegate {
    private let recorder: RecorderViewModel
    private let navigator: WindowNavigator
    private let preferences: AppPreferences
    private var statusItem: NSStatusItem?
    private var timerTask: Task<Void, Never>?

    init(recorder: RecorderViewModel, navigator: WindowNavigator, preferences: AppPreferences) {
        self.recorder = recorder
        self.navigator = navigator
        self.preferences = preferences
    }

    func start() {
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.start()
            }
        }
    }

    private func update() {
        guard let clock = recorder.activeClock else {
            stopShowing()
            return
        }
        if preferences.settings.showsMenuBarIcon {
            showStatusItem()
            refreshTitle(clock: clock)
        } else {
            removeStatusItem()
        }
        NSApp.dockTile.badgeLabel = Self.dockBadge
        if clock.isPaused {
            timerTask?.cancel()
            timerTask = nil
        } else if timerTask == nil {
            timerTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    self?.refreshTitle()
                }
            }
        }
    }

    private func showStatusItem() {
        guard statusItem == nil else {
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.button?.setAccessibilityLabel(String(localized: "Verbatim recording"))
        statusItem = item
    }

    private func stopShowing() {
        timerTask?.cancel()
        timerTask = nil
        removeStatusItem()
        NSApp.dockTile.badgeLabel = nil
    }

    private func removeStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    private func refreshTitle(clock: RecordingClock? = nil) {
        guard let clock = clock ?? recorder.activeClock, let button = statusItem?.button else {
            return
        }
        let timer = RecordingClock.timerText(for: clock.elapsed(at: .now))
        let dotColor: NSColor = clock.isPaused ? .tertiaryLabelColor : .systemRed
        let title = NSMutableAttributedString(
            string: "● ",
            attributes: [.foregroundColor: dotColor, .font: NSFont.systemFont(ofSize: 10)]
        )
        title.append(
            NSAttributedString(
                string: timer,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]
            )
        )
        button.attributedTitle = title
    }

    // MARK: - NSMenuDelegate

    /// Rebuilds the menu each time it opens, so Pause or Resume and the header reflect the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let current = RecordingMenus.statusMenu(recorder: recorder, navigator: navigator)
        menu.removeAllItems()
        menu.autoenablesItems = current.autoenablesItems
        for item in current.items {
            current.removeItem(item)
            menu.addItem(item)
        }
    }

    /// A single space draws the badge as a plain red dot, as in the design, rather than a count.
    private static let dockBadge = " "
}
