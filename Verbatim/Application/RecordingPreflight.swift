import Foundation

/// The checks before a recording may create anything: the configuration, macOS permissions and disk space.
struct RecordingPreflight {
    let permissions: any CapturePermissions
    let destinations: any RecordingDestinationStore

    /// Requests whatever permission is still undecided, which can show a system prompt.
    func check(_ configuration: RecordingConfiguration) async throws(RecordingFailure) {
        try configuration.validate()
        try await ensurePermissions(for: configuration)
        try await ensureDiskSpace(for: configuration)
    }

    private func ensurePermissions(for configuration: RecordingConfiguration) async throws(RecordingFailure) {
        if configuration.requiresScreenCaptureAccess {
            let hasAccess = permissions.hasScreenCaptureAccess()
            let isGranted = hasAccess ? true : await permissions.requestScreenCaptureAccess()
            guard isGranted else {
                throw .screenCaptureDenied
            }
        }
        if configuration.requiresMicrophoneAccess {
            let isGranted: Bool
            switch permissions.microphoneAccess() {
            case .granted: isGranted = true
            case .denied: isGranted = false
            case .notDetermined: isGranted = await permissions.requestMicrophoneAccess()
            }
            guard isGranted else {
                throw .microphoneDenied
            }
        }
    }

    private func ensureDiskSpace(for configuration: RecordingConfiguration) async throws(RecordingFailure) {
        let location = await destinations.currentLocation()
        let assessment = DiskSpacePolicy.assess(
            freeBytes: location.availableBytes,
            bytesPerSecond: configuration.estimatedBytesPerSecond
        )
        // An inaccessible folder reports no free space, so it must fail as a folder problem instead.
        if location.isAccessible, assessment == .insufficient {
            throw .insufficientDiskSpace(availableBytes: location.availableBytes)
        }
    }
}
