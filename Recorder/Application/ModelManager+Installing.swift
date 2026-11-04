import Foundation
import os

/// The install lifecycle: requests, the task doing the work, and how each way of ending affects the model.
extension ModelManager {
    /// Starts installing a model, or waits for the current recording to end. Ignored unless the model can accept a
    /// download, which is what prevents duplicates. Also serves as Retry.
    func download(_ id: SpeechModel.ID) {
        guard let model = model(withID: id) else {
            return
        }
        let current = state(of: id)
        guard current.acceptsDownload else {
            Self.logger.notice("Ignored a download request for \(id, privacy: .public)")
            return
        }
        guard supportedModelIDs.contains(id) else {
            setState(.failed(.unsupportedOnThisMac), for: id)
            return
        }
        // A damaged file can look current to the downloader, which would keep it, so those start over.
        if current == .failed(.damagedInstallation) {
            filesToDiscardFirst.insert(id)
        }
        startOrWait(model, progress: nil)
    }

    /// Stops an install and removes its partial files.
    func cancelDownload(_ id: SpeechModel.ID) {
        guard let model = model(withID: id), state(of: id).isInstalling else {
            return
        }
        filesToDiscardFirst.remove(id)
        setState(.notInstalled, for: id)
        if let install = installs[id] {
            stopReasons[install.token] = .cancelled
            install.task.cancel()
        } else {
            discardFilesOfCancelledInstall(of: model)
        }
    }

    /// Tracked like an install, because a new download of the model has to wait until this is done.
    private func discardFilesOfCancelledInstall(of model: SpeechModel) {
        let token = UUID()
        let task = Task {
            await discardFiles(of: model)
            await refreshStorageUsage()
            if installs[model.id]?.token == token {
                installs[model.id] = nil
            }
        }
        installs[model.id] = ActiveInstall(token: token, task: task)
    }

    func pauseInstalls() {
        for (id, install) in installs where state(of: id).isInstalling {
            stopReasons[install.token] = .pausedForRecording
            install.task.cancel()
            setState(.waitingForRecording(lastProgress(of: id)), for: id)
        }
    }

    func resumeWaitingInstalls() {
        for model in catalog {
            if case .waitingForRecording(let progress) = state(of: model.id) {
                startOrWait(model, progress: progress)
            }
        }
    }

    private func lastProgress(of id: SpeechModel.ID) -> ModelDownloadProgress? {
        if case .downloading(let progress) = state(of: id) {
            return progress
        }
        return nil
    }

    private func startOrWait(_ model: SpeechModel, progress: ModelDownloadProgress?) {
        guard !isRecordingActive else {
            setState(.waitingForRecording(progress), for: model.id)
            return
        }
        setState(.downloading(progress), for: model.id)
        let token = UUID()
        // An install that was just stopped may still be unwinding, and both would otherwise use the same files.
        let previous = installs[model.id]?.task
        let task = Task {
            await previous?.value
            await runInstall(of: model, token: token)
        }
        installs[model.id] = ActiveInstall(token: token, task: task)
    }

    private func runInstall(of model: SpeechModel, token: UUID) async {
        do {
            let files = try await installFiles(of: model, token: token)
            // Nothing suspends from here to the state change, so a cancel cannot slip in between.
            try Task.checkCancellation()
            registry.artifactSizes[model.id] = files.artifact.totalBytes
            registry.installations[model.id] = ModelInstallation(installedAt: now(), artifact: files.artifact)
            setState(.installed(sizeBytes: files.sizeBytes), for: model.id)
            selectIfFirstInstalled(model.id)
            await saveRegistry()
        } catch {
            await handleInstallEnd(of: model, token: token, error: error)
        }
        if installs[model.id]?.token == token {
            installs[model.id] = nil
        }
        await refreshStorageUsage()
    }

    /// Runs the work off the main actor while its events come back in order. All of them are applied before this
    /// returns, so the outcome can never overtake the last phase.
    private func installFiles(of model: SpeechModel, token: UUID) async throws -> ModelFileWorkflow.InstalledFiles {
        let (events, continuation) = AsyncStream.makeStream(of: ModelFileWorkflow.InstallEvent.self)
        let observer = Task {
            for await event in events where installs[model.id]?.token == token {
                apply(event, to: model.id)
            }
        }
        do {
            if filesToDiscardFirst.remove(model.id) != nil {
                await discardFiles(of: model)
            }
            let files = try await workflow.install(model, onEvent: { continuation.yield($0) })
            continuation.finish()
            await observer.value
            return files
        } catch {
            continuation.finish()
            await observer.value
            throw error
        }
    }

    /// The first model is selected, so there is something to use without another step. An unavailable selection stays,
    /// and so does having none among other installed models: those are the user's to change.
    private func selectIfFirstInstalled(_ id: SpeechModel.ID) {
        let hasOtherInstalledModel = catalog.contains { $0.id != id && state(of: $0.id).isInstalled }
        if selectedModelID == nil, !hasOtherInstalledModel {
            setSelection(id)
        }
    }

    /// Only a download in progress moves on: an event can arrive after the install was paused or has ended.
    private func apply(_ event: ModelFileWorkflow.InstallEvent, to id: SpeechModel.ID) {
        guard case .downloading = state(of: id) else {
            return
        }
        switch event {
        case .progress(let progress): setState(.downloading(progress), for: id)
        case .verifying: setState(.verifying, for: id)
        }
    }

    /// Whoever cancelled or paused has already set the state, and a newer request may be underway; only a genuine
    /// failure changes it here.
    private func handleInstallEnd(of model: SpeechModel, token: UUID, error: any Error) async {
        switch stopReasons.removeValue(forKey: token) {
        case .cancelled:
            await discardFiles(of: model)
        case .pausedForRecording:
            break
        case nil:
            let failure = Self.failure(from: error)
            Self.logger.error("Could not install \(model.id, privacy: .public): \(String(describing: error))")
            if case .verificationFailed = failure {
                // The downloader would trust these files on retry, so they cannot stay.
                await discardFiles(of: model)
            }
            setState(.failed(failure), for: model.id)
        }
    }

    private static func failure(from error: any Error) -> ModelManagementError {
        if let failure = error as? ModelManagementError {
            return failure
        }
        if error is CancellationError {
            return .interruptedDownload
        }
        return .downloadFailed(detail: error.localizedDescription)
    }

    private func discardFiles(of model: SpeechModel) async {
        do {
            try await workflow.provider.removeFiles(of: model, includingTokenizer: !isTokenizerShared(by: model))
        } catch {
            Self.logger.error("Could not discard files of \(model.id, privacy: .public): \(String(describing: error))")
        }
    }

    /// Conservative: any other model that is not plainly absent may be relying on the tokenizer.
    func isTokenizerShared(by model: SpeechModel) -> Bool {
        catalog.contains {
            $0.id != model.id && $0.tokenizerRepository == model.tokenizerRepository
                && state(of: $0.id) != .notInstalled
        }
    }
}
