import Foundation

/// Which issue the callout shows, and what its buttons do.
extension RecorderViewModel {
    var issue: RecorderIssue? {
        if preview.isActive {
            return preview.issue
        }
        if case .failed(let failure) = coordinator.state {
            return failure.presentedIssue
        }
        return actionIssue
            ?? selection.lostSourceIssue
            ?? sourceDiscoveryIssue
            ?? coordinator.lastOutcome.flatMap(RecorderIssue.init)
            ?? configurationIssue
    }

    func performIssuePrimaryAction() {
        if let issue {
            perform(issue.primaryAction, for: issue)
        }
    }

    func performIssueSecondaryAction() {
        if let issue {
            perform(issue.secondaryAction, for: issue)
        }
    }

    func clearIssue() {
        preview.issue = nil
        actionIssue = nil
        selection.lostSourceIssue = nil
        coordinator.acknowledgeFailure()
        coordinator.acknowledgeOutcome()
    }

    /// Clears a failure once the reason for it is gone, such as access granted in System Settings.
    func clearFailureThatNoLongerApplies() {
        let permissions = dependencies.permissions
        switch coordinator.state {
        case .failed(.screenCaptureDenied) where permissions.hasScreenCaptureAccess():
            coordinator.acknowledgeFailure()
        case .failed(.microphoneDenied) where permissions.microphoneAccess() == .granted:
            coordinator.acknowledgeFailure()
        case .failed(.insufficientDiskSpace):
            if let location, assessDiskSpace(at: location) != .insufficient {
                coordinator.acknowledgeFailure()
            }
        default:
            break
        }
        if actionIssue == .screenRecordingPermission, permissions.hasScreenCaptureAccess() {
            actionIssue = nil
        }
    }

    private func perform(_ action: RecorderIssueAction, for issue: RecorderIssue) {
        if let captureMode = action.captureMode {
            self.captureMode = captureMode
        }
        if let isEnabled = action.isMicrophoneEnabled {
            isMicrophoneEnabled = isEnabled
        }
        if let isEnabled = action.isSystemAudioEnabled {
            isSystemAudioEnabled = isEnabled
        }
        if let quality = action.quality {
            self.quality = quality
        }
        if action.isResolving {
            clearIssue()
        }
        if let effect = action.effect {
            perform(effect, for: issue)
        }
    }

    private func perform(_ effect: RecorderIssueAction.Effect, for issue: RecorderIssue) {
        switch effect {
        case .openSettings(let pane):
            let systemActions = dependencies.systemActions
            Task {
                await systemActions.open(pane)
            }
        case .selectAvailableWindow:
            selection.selectedWindowID = selection.selectedWindow?.id ?? selection.windows.first?.id
        case .selectMainDisplay:
            selection.selectedDisplayID = selection.displays.first?.id
        case .selectDefaultMicrophone:
            selection.selectedMicrophoneID = selection.microphones.first?.id
        case .chooseFolder:
            isChoosingFolder = true
        case .useDefaultFolder:
            useDefaultFolder()
        case .retryRecording:
            startRecording()
        case .reloadSources:
            Task {
                await refresh()
            }
        case .revealRecording:
            revealRecording(for: issue)
        }
    }

    private func revealRecording(for issue: RecorderIssue) {
        if case .finalizationFailed(_, let directoryPath) = issue {
            reveal(URL(fileURLWithPath: directoryPath, isDirectory: true))
        } else if let url = coordinator.lastOutcome?.destination.directoryURL ?? location?.url {
            reveal(url)
        }
    }

    /// Problems visible in the settings themselves, before any attempt to start.
    private var configurationIssue: RecorderIssue? {
        if captureMode == .audioOnly, !isMicrophoneEnabled, !isSystemAudioEnabled {
            return .noAudioSource
        }
        if isMicrophoneEnabled, isMicrophoneAccessDenied {
            return .microphonePermission
        }
        if hasLoadedSources, isMicrophoneEnabled, selection.microphones.isEmpty {
            return .microphoneUnavailable(name: "")
        }
        guard let location else {
            return nil
        }
        guard location.isAccessible else {
            return .folderAccess(path: location.displayPath)
        }
        return diskIssue(at: location)
    }

    private func diskIssue(at location: RecordingLocation) -> RecorderIssue? {
        switch assessDiskSpace(at: location) {
        case .sufficient:
            return nil
        case .insufficient:
            return .insufficientDiskSpace(freeBytes: location.availableBytes)
        case .low(let minutesRemaining):
            let settings = captureMode.capturesVideo ? "\(quality.rawValue), \(frameRate.rawValue) fps" : "audio only"
            return .lowDiskSpace(
                freeBytes: location.availableBytes,
                minutesRemaining: minutesRemaining,
                settings: settings
            )
        }
    }

    private func assessDiskSpace(at location: RecordingLocation) -> DiskSpacePolicy.Assessment {
        DiskSpacePolicy.assess(
            freeBytes: location.availableBytes,
            bytesPerSecond: makeConfiguration().estimatedBytesPerSecond
        )
    }
}
