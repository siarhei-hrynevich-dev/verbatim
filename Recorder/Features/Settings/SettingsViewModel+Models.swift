import Foundation

/// Speech and embedding model management, the search index, and the simulation that advances them.
extension SettingsViewModel {
    func state(of modelID: SpeechModel.ID) -> ModelInstallState {
        modelStates[modelID] ?? .notInstalled
    }

    func isDefault(_ modelID: SpeechModel.ID) -> Bool {
        modelID == defaultModelID && state(of: modelID).isInstalled
    }

    /// The default model cannot be removed until another one is made the default.
    func canRemove(_ modelID: SpeechModel.ID) -> Bool {
        state(of: modelID).isInstalled && !isDefault(modelID)
    }

    func download(_ modelID: SpeechModel.ID) {
        guard state(of: modelID) == .notInstalled else {
            return
        }
        modelStates[modelID] = .downloading(progress: 0)
    }

    func cancelDownload(_ modelID: SpeechModel.ID) {
        guard state(of: modelID).isBusy else {
            return
        }
        modelStates[modelID] = .notInstalled
    }

    func makeDefault(_ modelID: SpeechModel.ID) {
        guard state(of: modelID).isInstalled else {
            return
        }
        defaultModelID = modelID
    }

    func requestRemoval(of modelID: SpeechModel.ID) {
        guard canRemove(modelID) else {
            return
        }
        sheet = .removeModel(modelID)
    }

    /// Simulates deleting the model files; transcripts made with the model are kept.
    func confirmRemoval(of modelID: SpeechModel.ID) {
        if canRemove(modelID) {
            modelStates[modelID] = .notInstalled
        }
        sheet = nil
    }

    func speechModel(withID modelID: SpeechModel.ID) -> SpeechModel? {
        data.speechModels.first { $0.id == modelID }
    }

    /// Seconds left at the simulated download speed, never shown as less than five.
    func secondsLeft(downloading model: SpeechModel, progress: Double) -> Int {
        let megabytesLeft = (1 - progress) * Double(model.sizeMegabytes)
        return max(5, Int((megabytesLeft / Self.downloadMegabytesPerSecond).rounded()))
    }

    // MARK: - Semantic search

    func downloadEmbeddingModel() {
        guard isSemanticSearchEnabled, embeddingState == .notInstalled else {
            return
        }
        embeddingState = .downloading(progress: 0)
    }

    func cancelEmbeddingDownload() {
        embeddingState = .notInstalled
    }

    func removeEmbeddingModel() {
        embeddingState = .notInstalled
        indexedRecordingCount = 0
    }

    var isSearchIndexAvailable: Bool {
        isSemanticSearchEnabled && embeddingState.isInstalled
    }

    var indexStatus: IndexStatus {
        guard isSemanticSearchEnabled else {
            return .off
        }
        guard embeddingState.isInstalled else {
            return .waitingForModel
        }
        if indexedRecordingCount < data.recordingCount {
            return .indexing(indexed: indexedRecordingCount, total: data.recordingCount)
        }
        return .upToDate
    }

    /// Simulates re-reading every transcript; recordings are not modified.
    func rebuildSearchIndex() {
        guard isSearchIndexAvailable else {
            return
        }
        indexedRecordingCount = 0
    }

    // MARK: - Simulation

    /// Advances simulated work every 200 ms until cancelled. The window runs it with `.task`, so it stops when
    /// Settings closes; real downloads will belong to an application service that outlives the window.
    func runSimulation() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: Self.simulationInterval)
            } catch {
                return
            }
            advanceSimulation()
        }
    }

    /// One simulation step, matching the design prototype's rates.
    func advanceSimulation() {
        for (modelID, state) in modelStates {
            modelStates[modelID] = Self.advanced(state)
        }
        if case .downloading(let progress) = embeddingState {
            let next = progress + Self.embeddingStep
            embeddingState = next >= 1 ? .installed : .downloading(progress: next)
        }
        let indexesThisTick = tick % Self.indexTickInterval == 0
        if isSearchIndexAvailable, indexedRecordingCount < data.recordingCount, indexesThisTick {
            indexedRecordingCount += 1
        }
        if updateStatus == .checking, tick - updateCheckStartTick > Self.updateCheckTicks {
            updateStatus = .upToDate
        }
        tick += 1
    }

    private static func advanced(_ state: ModelInstallState) -> ModelInstallState {
        switch state {
        case .downloading(let progress):
            let next = progress + downloadStep
            return next >= 1 ? .preparing(progress: 0) : .downloading(progress: next)
        case .preparing(let progress):
            let next = progress + preparingStep
            return next >= 1 ? .installed : .preparing(progress: next)
        case .notInstalled, .installed:
            return state
        }
    }

    static let simulationInterval = Duration.milliseconds(200)
    private static let downloadStep = 0.004
    private static let preparingStep = 0.012
    private static let embeddingStep = 0.03
    private static let indexTickInterval = 5
    private static let updateCheckTicks = 10
    /// The prototype's assumed download speed, used for the time-left estimate.
    private static let downloadMegabytesPerSecond = 30.0
}
