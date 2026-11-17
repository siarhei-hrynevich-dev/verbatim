import AppKit
import os

/// Opens `verbatim://recording/<id>?t=<seconds>` links, which AI agents give when citing a recording, in the Viewer at
/// that moment.
extension AppDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let link = RecordingLink(url: url) else {
                linkLogger.error("Ignored a link that names no recording: \(url.absoluteString, privacy: .public)")
                continue
            }
            viewerViewModel.open(recordingID: link.recordingID, at: link.time)
            navigator.showViewer()
        }
    }
}

private let linkLogger = Logger(category: "Links")
