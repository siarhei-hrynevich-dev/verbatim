import Foundation

/// What follows from changing a setting: saving it, retiring stale failures and keeping the meters in step.
extension RecorderViewModel {
    func chooseFolder(_ url: URL) {
        Task {
            await useChosenFolder(url)
        }
    }

    /// A failure from the last attempt is stale once the user changes what would be recorded.
    func settingsDidChange(reloadsSources: Bool = false) {
        guard !preview.isActive else {
            return
        }
        savePreferences()
        coordinator.acknowledgeFailure()
        updateLevelPreview()
        guard reloadsSources else {
            return
        }
        if captureMode != .window, case .windowUnavailable = selection.lostSourceIssue {
            selection.lostSourceIssue = nil
        }
        if captureMode != .screen, case .displayUnavailable = selection.lostSourceIssue {
            selection.lostSourceIssue = nil
        }
        if captureMode != .window, actionIssue == .screenRecordingPermission {
            actionIssue = nil
        }
        Task {
            await requestWindowAccessIfNeeded()
            await refresh()
        }
    }

    /// Listing windows needs Screen Recording access, and choosing Window is the moment to ask for it.
    private func requestWindowAccessIfNeeded() async {
        let permissions = dependencies.permissions
        guard captureMode == .window, !permissions.hasScreenCaptureAccess() else {
            return
        }
        let isGranted = await permissions.requestScreenCaptureAccess()
        actionIssue = isGranted ? nil : .screenRecordingPermission
    }

    func microphoneEnabledDidChange() {
        if !isMicrophoneEnabled, case .microphoneUnavailable = selection.lostSourceIssue {
            selection.lostSourceIssue = nil
        }
        settingsDidChange()
        let permissions = dependencies.permissions
        guard !preview.isActive, isMicrophoneEnabled, permissions.microphoneAccess() == .notDetermined else {
            return
        }
        Task {
            _ = await permissions.requestMicrophoneAccess()
            updateLevelPreview()
        }
    }

    func savePreferences() {
        guard !preview.isActive else {
            return
        }
        let rememberedWindow = selection.rememberedWindow
        dependencies.preferencesStore.save(
            RecordingPreferences(
                captureMode: captureMode,
                displayID: selection.selectedDisplayID,
                windowID: selection.selectedWindowID,
                windowBundleIdentifier: rememberedWindow?.bundleIdentifier,
                windowTitle: rememberedWindow?.title,
                microphoneID: selection.selectedMicrophoneID,
                isMicrophoneEnabled: isMicrophoneEnabled,
                isSystemAudioEnabled: isSystemAudioEnabled,
                quality: quality,
                frameRate: frameRate,
                transcribesWhenFinished: transcribesWhenFinished
            )
        )
    }

    /// Goes back to the saved settings after a design scenario, which is the only other thing that changes them.
    func restoreSavedSettings() {
        let preferences = dependencies.preferencesStore.load()
        selection.restore(preferences)
        captureMode = preferences.captureMode
        isMicrophoneEnabled = preferences.isMicrophoneEnabled
        isSystemAudioEnabled = preferences.isSystemAudioEnabled
        quality = preferences.quality
        frameRate = preferences.frameRate
        transcribesWhenFinished = preferences.transcribesWhenFinished
    }

    /// Runs the meters for the sources that are enabled and already permitted. It never prompts.
    func updateLevelPreview() {
        guard isSetupVisible, phase == .ready, !preview.isActive else {
            levelPreview.stop()
            return
        }
        let permissions = dependencies.permissions
        levelPreview.run(
            microphone: isMicrophoneEnabled && permissions.microphoneAccess() == .granted ? selectedMicrophone : nil,
            capturesSystemAudio: isSystemAudioEnabled && permissions.hasScreenCaptureAccess()
        )
    }
}
