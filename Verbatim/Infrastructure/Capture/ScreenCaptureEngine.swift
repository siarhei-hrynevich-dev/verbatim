import Foundation
import OSLog
import ScreenCaptureKit

/// Starts capture with ScreenCaptureKit and AVFoundation.
struct ScreenCaptureEngine: CaptureEngine {
    private static let logger = Logger(category: "Capture")

    // MARK: - CaptureEngine

    func startSession(configuration: RecordingConfiguration, outputURL: URL) async throws -> any CaptureSession {
        do {
            let content = try await Self.shareableContentIfNeeded(for: configuration)
            var plan = CapturePlan(microphone: configuration.microphone)
            if configuration.capturesSystemAudio {
                plan.systemAudioDisplay = try Self.systemAudioDisplay(in: content)
            }
            plan.video = try Self.videoPlan(for: configuration, content: content)
            let writer = try Self.makeWriter(
                configuration: configuration,
                videoSize: plan.video?.size,
                outputURL: outputURL
            )
            let session = LiveCaptureSession(writer: writer, outputURL: outputURL)
            do {
                try await session.start(plan)
            } catch {
                await session.stopCapture()
                // Closes the file for what was captured before the failure; the start failure is what gets reported.
                _ = try? await session.finalize()
                throw error
            }
            await monitorVideoSource(of: configuration, in: session)
            return session
        } catch {
            throw Self.startFailure(from: error)
        }
    }

    func startLevelPreview(microphone: Microphone?, capturesSystemAudio: Bool) async throws -> any CaptureSession {
        var plan = CapturePlan(microphone: microphone)
        if capturesSystemAudio {
            plan.systemAudioDisplay = try Self.systemAudioDisplay(in: await Self.shareableContent())
        }
        let session = LiveCaptureSession(writer: nil, outputURL: nil)
        try await session.start(plan)
        return session
    }

    // MARK: - Starting a session

    private func monitorVideoSource(
        of configuration: RecordingConfiguration,
        in session: LiveCaptureSession
    ) async {
        switch configuration.target {
        case .display(let display):
            await session.monitorVideoSource { await Self.isDisplayAvailable(display) }
        case .window(let window):
            await session.monitorVideoSource { await Self.isWindowAvailable(window) }
        case .audioOnly, nil:
            break
        }
    }

    private static func shareableContentIfNeeded(
        for configuration: RecordingConfiguration
    ) async throws -> SCShareableContent? {
        guard configuration.requiresScreenCaptureAccess else {
            return nil
        }
        return try await shareableContent()
    }

    /// ScreenCaptureKit occasionally reports no displays for a moment, so that gets a few short retries.
    private static func shareableContent() async throws -> SCShareableContent {
        var content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        for _ in 0..<displayListRetries where content.displays.isEmpty {
            try await Task.sleep(for: .milliseconds(200))
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        }
        return content
    }

    /// Audio needs a display to attach its stream to. Going without one would silently lose system audio.
    private static func systemAudioDisplay(in content: SCShareableContent?) throws -> SCDisplay {
        guard let display = content?.displays.first else {
            throw RecordingFailure.initializationFailed(
                detail: String(localized: "macOS reported no displays to capture system audio from.")
            )
        }
        return display
    }

    private static let displayListRetries = 5

    private static func videoPlan(
        for configuration: RecordingConfiguration,
        content: SCShareableContent?
    ) throws -> CapturePlan.Video? {
        guard let content else {
            return nil
        }
        let filter: SCContentFilter
        let sizePoints: CGSize
        switch configuration.target {
        case .display(let display):
            guard
                let scDisplay = content.displays.first(where: {
                    CaptureSourceDiscovery.stableID(of: $0.displayID) == display.id
                })
            else {
                throw RecordingFailure.displayUnavailable(name: display.name)
            }
            filter = SCContentFilter(display: scDisplay, excludingApplications: [], exceptingWindows: [])
            sizePoints = CGSize(width: scDisplay.width, height: scDisplay.height)
        case .window(let window):
            guard let scWindow = content.windows.first(where: { String($0.windowID) == window.id }) else {
                throw RecordingFailure.windowUnavailable(name: window.title)
            }
            filter = SCContentFilter(desktopIndependentWindow: scWindow)
            sizePoints = scWindow.frame.size
        case .audioOnly, nil:
            return nil
        }
        // ScreenCaptureKit sizes are in points; Retina displays have more pixels than that.
        let source = PixelSize(
            width: pixelDimension(sizePoints.width, scale: filter.pointPixelScale),
            height: pixelDimension(sizePoints.height, scale: filter.pointPixelScale)
        )
        return CapturePlan.Video(
            filter: filter,
            size: configuration.quality.outputSize(forSource: source),
            frameRate: configuration.frameRate
        )
    }

    private static func makeWriter(
        configuration: RecordingConfiguration,
        videoSize: PixelSize?,
        outputURL: URL
    ) throws -> MediaFileWriter {
        return try MediaFileWriter(
            url: outputURL,
            video: videoSize.map { .init(size: $0, frameRate: configuration.frameRate) },
            audioSources: configuration.audioSources
        )
    }

    private static func startFailure(from error: any Error) -> RecordingFailure {
        if let failure = error as? RecordingFailure {
            return failure
        }
        let nsError = error as NSError
        let isDeclined = nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.userDeclined.rawValue
        if isDeclined {
            return .screenCaptureDenied
        }
        return .initializationFailed(detail: error.localizedDescription)
    }

    private static func pixelDimension(_ points: CGFloat, scale: Float) -> Int {
        Int((points * CGFloat(max(scale, 1))).rounded())
    }

    // MARK: - Source availability

    /// Includes off-screen windows, because a window on another Space or a hidden app has not gone away.
    private static func isWindowAvailable(_ window: CaptureWindow) async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            return content.windows.contains { String($0.windowID) == window.id }
        } catch {
            logger.notice("Could not check a window's availability: \(String(describing: error))")
            return true
        }
    }

    private static func isDisplayAvailable(_ display: CaptureDisplay) async -> Bool {
        do {
            let content = try await SCShareableContent.current
            return content.displays.contains { CaptureSourceDiscovery.stableID(of: $0.displayID) == display.id }
        } catch {
            logger.notice("Could not check a display's availability: \(String(describing: error))")
            return true
        }
    }
}
