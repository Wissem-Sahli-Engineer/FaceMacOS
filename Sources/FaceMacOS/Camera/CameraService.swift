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
    private var isConfigured = false
    private var frameHandler: ((CVPixelBuffer) -> Void)?

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start(onFrame: @escaping (CVPixelBuffer) -> Void) throws {
        try configureIfNeeded()
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

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        guard let device = discovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
            ?? discovery.devices.first
            ?? AVCaptureDevice.default(for: .video)
        else { throw CameraError.noDevice }

        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw CameraError.cannotAddOutput
        }
        session.addOutput(output)
        isConfigured = true
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
