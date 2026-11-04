import AVFoundation
import CoreGraphics

/// macOS privacy state for capture. Both requests can show a system prompt, so call them only for a user action.
struct SystemCapturePermissions: CapturePermissions {
    func hasScreenCaptureAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenCaptureAccess() async -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func microphoneAccess() -> MicrophoneAccess {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: .notDetermined
        case .authorized: .granted
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}
