import AppKit
import ImageIO
import OSLog
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Lists displays, windows and microphones, and takes window thumbnails.
struct CaptureSourceDiscovery: CaptureSourceProviding {
    /// Without Screen Recording access, ScreenCaptureKit would prompt. Displays then come from CoreGraphics so the
    /// picker can still show them, and windows stay unknown until access is granted.
    func availableSources() async throws -> CaptureSources {
        let names = await Self.displayNames()
        guard CGPreflightScreenCaptureAccess() else {
            return CaptureSources(displays: Self.activeDisplays(names: names), windows: [])
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        // ScreenCaptureKit occasionally reports no displays for a moment; that must not read as all of them gone.
        let displays =
            content.displays.isEmpty
            ? Self.activeDisplays(names: names)
            : content.displays.map { Self.captureDisplay(id: $0.displayID, names: names) }
        return CaptureSources(displays: displays, windows: content.windows.compactMap(Self.captureWindow))
    }

    func availableMicrophones() async -> [Microphone] {
        MicrophoneCapture.availableMicrophones()
    }

    func windowThumbnails(for windowIDs: [CaptureWindow.ID]) async -> [CaptureWindow.ID: Data] {
        guard CGPreflightScreenCaptureAccess() else {
            return [:]
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            var thumbnails: [CaptureWindow.ID: Data] = [:]
            for window in content.windows where windowIDs.contains(String(window.windowID)) {
                if let thumbnail = await Self.thumbnail(of: window) {
                    thumbnails[String(window.windowID)] = thumbnail
                }
            }
            return thumbnails
        } catch {
            Self.logger.notice("Could not list windows for thumbnails: \(String(describing: error))")
            return [:]
        }
    }

    /// Display numbers can change between connections; the UUID identifies the same display again.
    static func stableID(of displayID: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return String(displayID)
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    // MARK: - Mapping

    private static func captureWindow(_ window: SCWindow) -> CaptureWindow? {
        guard window.windowLayer == 0, let application = window.owningApplication,
            application.bundleIdentifier != Bundle.main.bundleIdentifier,
            let title = window.title, !title.isEmpty,
            window.frame.width >= minimumWindowSidePoints, window.frame.height >= minimumWindowSidePoints
        else {
            return nil
        }
        return CaptureWindow(
            id: String(window.windowID),
            appName: application.applicationName,
            title: title,
            bundleIdentifier: application.bundleIdentifier
        )
    }

    private static func captureDisplay(id: CGDirectDisplayID, names: [CGDirectDisplayID: String]) -> CaptureDisplay {
        let mode = CGDisplayCopyDisplayMode(id)
        return CaptureDisplay(
            id: stableID(of: id),
            name: names[id] ?? String(localized: "Display"),
            pixelWidth: mode?.pixelWidth ?? CGDisplayPixelsWide(id),
            pixelHeight: mode?.pixelHeight ?? CGDisplayPixelsHigh(id)
        )
    }

    private static func activeDisplays(names: [CGDirectDisplayID: String]) -> [CaptureDisplay] {
        var ids = [CGDirectDisplayID](repeating: 0, count: maximumDisplays)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(maximumDisplays), &ids, &count) == .success else {
            return []
        }
        return ids.prefix(Int(count)).map { captureDisplay(id: $0, names: names) }
    }

    /// ScreenCaptureKit does not name displays.
    @MainActor
    private static func displayNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[number.uint32Value] = screen.localizedName
            }
        }
        return names
    }

    // MARK: - Thumbnails

    private static func thumbnail(of window: SCWindow) async -> Data? {
        let configuration = SCStreamConfiguration()
        let aspectRatio = window.frame.height / max(window.frame.width, 1)
        configuration.width = thumbnailWidthPixels
        configuration.height = max(Int(CGFloat(thumbnailWidthPixels) * aspectRatio), 2)
        configuration.showsCursor = false
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: configuration
            )
            return jpegData(from: image)
        } catch {
            logger.info("No thumbnail for a window: \(String(describing: error))")
            return nil
        }
    }

    private static func jpegData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        let type = UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Small helper windows and panels are not useful recording targets.
    private static let minimumWindowSidePoints: CGFloat = 100
    private static let maximumDisplays = 16
    /// Twice the width of a tile in the three-column grid, for Retina displays.
    private static let thumbnailWidthPixels = 280
    private static let logger = Logger(subsystem: "dev.local.Recorder", category: "Capture")
}
