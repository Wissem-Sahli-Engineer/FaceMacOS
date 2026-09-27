import AVFoundation

final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum CameraError: Error {
        case noDevice
        case cannotAddInput
        case cannotAddOutput
    }

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "facemacos.camera.session")
    private let videoQueue = DispatchQueue(label: "facemacos.camera.video", qos: .userInteractive)
    private var input: AVCaptureDeviceInput?
    private var needsReconfigure = false
    private var frameHandler: ((CVPixelBuffer) -> Void)?

    override init() {
        super.init()
        // Closing the lid or sleeping can leave the session in an error state; rebuild it on the next start.
        NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] _ in
            self?.sessionQueue.async { self?.needsReconfigure = true }
        }
    }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start(onFrame: @escaping (CVPixelBuffer) -> Void) throws {
        try sessionQueue.sync { try configureIfNeeded() }
        videoQueue.sync { frameHandler = onFrame }
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        videoQueue.async { self.frameHandler = nil }
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Runs on sessionQueue.
    private func configureIfNeeded() throws {
        if let input, input.device.isConnected, !needsReconfigure { return }
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.commitConfiguration()
        input = nil
        needsReconfigure = false

        let external: AVCaptureDevice.DeviceType
        if #available(macOS 14, *) { external = .external } else { external = .externalUnknown }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, external],
            mediaType: .video,
            position: .unspecified
        )
        guard let device = discovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
            ?? discovery.devices.first
            ?? AVCaptureDevice.default(for: .video)
        else { throw CameraError.noDevice }

        let newInput = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard session.canAddInput(newInput) else { throw CameraError.cannotAddInput }
        session.addInput(newInput)
        guard session.canAddOutput(output) else {
            session.removeInput(newInput)
            throw CameraError.cannotAddOutput
        }
        session.addOutput(output)
        input = newInput
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let handler = frameHandler, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        handler(buffer)
    }
}

/// One camera run feeding analyzed frames into an AsyncStream; finishes on stop() or timeout.
final class FrameSession {
    let stream: AsyncStream<FaceAnalysis>
    private let continuation: AsyncStream<FaceAnalysis>.Continuation
    private let camera: CameraService
    private var watchdog: Task<Void, Never>?

    init(camera: CameraService, analyzer: FaceAnalyzer, timeout: Duration, maxFPS: Double) throws {
        (stream, continuation) = AsyncStream.makeStream(of: FaceAnalysis.self, bufferingPolicy: .bufferingNewest(1))
        self.camera = camera
        let continuation = self.continuation
        let minimumInterval = 1 / maxFPS
        var lastAnalysis: TimeInterval = 0
        try camera.start { buffer in
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastAnalysis >= minimumInterval else { return }
            lastAnalysis = now
            continuation.yield(analyzer.analyze(buffer))
        }
        watchdog = Task {
            try? await Task.sleep(for: timeout)
            continuation.finish()
        }
    }

    func stop() {
        watchdog?.cancel()
        continuation.finish()
        camera.stop()
    }
}
