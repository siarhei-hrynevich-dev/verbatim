import AppKit
import SwiftUI

/// Calls `action` on a secondary click (right-click or Control-click) and lets every other event through.
///
/// SwiftUI only reports secondary clicks through `contextMenu`, which shows a native menu. The Library draws the
/// design's menu itself, so this overlay claims hit-testing only while a secondary click is being delivered.
struct SecondaryClickArea: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> ClickView {
        let view = ClickView()
        view.action = action
        return view
    }

    func updateNSView(_ view: ClickView, context: Context) {
        view.action = action
    }

    final class ClickView: NSView {
        var action: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, Self.isSecondaryClick(event) else {
                return nil
            }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            action?()
        }

        override func mouseDown(with event: NSEvent) {
            if Self.isSecondaryClick(event) {
                action?()
            } else {
                super.mouseDown(with: event)
            }
        }

        private static func isSecondaryClick(_ event: NSEvent) -> Bool {
            event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        }
    }
}
