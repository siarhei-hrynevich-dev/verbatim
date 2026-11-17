import AVFoundation
import CoreMedia

/// Captures one microphone with AVCaptureSession, so microphone-only recording needs no Screen Recording access.
///
/// Runs on its own queue because starting and stopping a capture session block.
actor MicrophoneCapture {
    private let queue = DispatchSerialQueue(label: "\(AppIdentity.bundleIdentifier).microphone", qos: .userInitiated)
    private let session = AVCaptureSession()
    private let events: AsyncStream<CaptureEvent>.Continuation
    private var output: SampleOutput?
    private var observers: [any NSObjectProtocol] = []

    init(events: AsyncStream<CaptureEvent>.Continuation) {
        self.events = events
    }

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// The system default comes first, as the choice used when none is remembered.
    nonisolated static func availableMicrophones() -> [Microphone] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID
        let microphones = discovery.devices.map { Microphone(id: $0.uniqueID, name: $0.localizedName) }
        return microphones.filter { $0.id == defaultID } + microphones.filter { $0.id != defaultID }
    }

    func start(_ microphone: Microphone, sink: CaptureSampleSink) throws(RecordingFailure) {
        guard let device = AVCaptureDevice(uniqueID: microphone.id) else {
            throw .microphoneUnavailable(name: microphone.name)
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw .microphoneUnavailable(name: microphone.name)
        }
        let dataOutput = Self.makeDataOutput()
        guard session.canAddInput(input), session.canAddOutput(dataOutput) else {
            throw .microphoneUnavailable(name: microphone.name)
        }
        session.addInput(input)
        session.addOutput(dataOutput)

        let output = SampleOutput(sink: sink, sessionClock: session.synchronizationClock)
        dataOutput.setSampleBufferDelegate(output, queue: sink.sampleQueue)
        self.output = output

        observeLoss(of: device)
        session.startRunning()
        guard session.isRunning else {
            stop()
            throw .microphoneUnavailable(name: microphone.name)
        }
    }

    /// Asks for mono 32-bit float whatever the device delivers, which the level meter and the writer rely on.
    nonisolated static func makeDataOutput() -> AVCaptureAudioDataOutput {
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: CaptureAudioFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        return output
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if session.isRunning {
            session.stopRunning()
        }
        output = nil
    }

    private func observeLoss(of device: AVCaptureDevice) {
        let events = events
        let notify: @Sendable (Notification) -> Void = { _ in
            events.yield(.microphoneLost)
        }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification,
                object: device,
                queue: nil,
                using: notify
            ),
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: nil,
                using: notify
            )
        ]
    }

    /// Moves samples to the host clock that ScreenCaptureKit timestamps use, so all tracks stay in sync.
    private final class SampleOutput: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, Sendable {
        private let sink: CaptureSampleSink
        private let sessionClock: CMClock?

        init(sink: CaptureSampleSink, sessionClock: CMClock?) {
            self.sink = sink
            self.sessionClock = sessionClock
        }

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            sink.deliverAudio(hostTimed(sampleBuffer), from: .microphone)
        }

        private func hostTimed(_ sample: CMSampleBuffer) -> CMSampleBuffer {
            let hostClock = CMClockGetHostTimeClock()
            guard let sessionClock, sessionClock != hostClock, let timings = try? sample.sampleTimingInfos() else {
                return sample
            }
            let converted = timings.map { timing in
                CMSampleTimingInfo(
                    duration: timing.duration,
                    presentationTimeStamp: CMSyncConvertTime(
                        timing.presentationTimeStamp,
                        from: sessionClock,
                        to: hostClock
                    ),
                    decodeTimeStamp: .invalid
                )
            }
            return (try? CMSampleBuffer(copying: sample, withNewTiming: converted)) ?? sample
        }
    }
}
