import CoreGraphics
import Foundation

enum AuthPhase: Equatable {
    case idle
    case scanning(hint: String)
    case enrolling(filled: Set<Int>, hint: String)
    case success(String)
    case failure(String)
}

enum PoseSectors {
    static let count = 8
    static let requiredToFinish = 7
    static let activationDistance = 0.10

    /// Sector index for a direction in degrees (0 = right, counter-clockwise, as seen in the mirrored preview).
    static func sector(forDegrees degrees: Double) -> Int {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360 + 22.5).truncatingRemainder(dividingBy: 360)
        return Int(normalized / 45) % count
    }
}

enum PresenceGoal {
    case faceAppears
    case faceAbsent(seconds: Double)
}

struct LiveStats {
    var status = "Starting camera…"
    var fps: Double = 0
    var faceRect: CGRect?
    var quality: Float = 0
    var score: Float?
    var eyeOpenness: Double = 0
    var blinks = 0
    var turnX: Double = 0
    var turnY: Double = 0
    var liveness = "—"
    var lastGesture: FaceGesture?
}

/// Tracks identity match (3-frame rolling score) and liveness over one scan.
final class Verifier {
    enum Outcome: Equatable {
        case searching
        case matched(livenessHint: String)
        case verified
    }

    private let template: FaceTemplate
    private let liveness: LivenessDetector
    private var recentScores: [Float] = []
    private(set) var score: Float?
    private(set) var isMatched = false

    init(template: FaceTemplate, liveness: LivenessDetector) {
        self.template = template
        self.liveness = liveness
    }

    func ingest(_ sample: FaceSample) -> Outcome {
        liveness.ingest(sample)
        if let embedding = sample.embedding {
            recentScores.append(template.score(embedding))
            if recentScores.count > 3 { recentScores.removeFirst() }
            let average = recentScores.reduce(0, +) / Float(recentScores.count)
            score = average
            isMatched = recentScores.count == 3 && average >= template.threshold
        }
        guard isMatched else { return .searching }
        let result = liveness.evaluate()
        return result.passed ? .verified : .matched(livenessHint: result.hint)
    }
}

@MainActor
final class FaceAuthenticator: ObservableObject {
    nonisolated static let recognitionFPS: Double = 20
    nonisolated static let presenceFPS: Double = 5

    @Published private(set) var phase: AuthPhase = .idle
    @Published private(set) var preview: CGImage?
    @Published private(set) var isEnrolled = false
    @Published private(set) var lastScore: Float?
    @Published private(set) var cameraError: String?
    @Published private(set) var isMonitoring = false
    @Published private(set) var liveFrame: CGImage?
    @Published private(set) var liveStats = LiveStats()

    let embedder: FaceEmbedder
    let spoofClassifier: SpoofClassifier?
    private let camera = CameraService()
    private let store = FaceStore()
    private let settings = AppSettings.shared
    private var template: FaceTemplate?
    private var activeSession: FrameSession?
    private var operationInProgress = false
    private var currentOperation = ""
    private var isLockScreenOperation = false
    private var dismissRequested = false
    private var monitorTask: Task<Void, Never>?

    var threshold: Float? { template?.threshold }
    var isBusy: Bool { operationInProgress }

    init() {
        embedder = Embedders.best()
        spoofClassifier = SpoofClassifier.load()
        reloadTemplate()
    }

    func deleteEnrollment() {
        store.delete()
        lastScore = nil
        reloadTemplate()
    }

    // MARK: - Enrollment

    @discardableResult
    func enroll() async -> Bool {
        guard await begin("enroll") else { return false }
        defer { end() }
        phase = .enrolling(filled: [], hint: "Position your face in the frame")
        guard let session = await openSession(timeout: .seconds(45), options: AnalyzerOptions(facePreview: true)) else {
            return await finish(false, cameraError ?? "No camera available")
        }

        let liveness = LivenessDetector(requireBlink: true)
        var baseline: [(x: Double, y: Double)] = []
        var centerEmbeddings: [[Float]] = []
        var sectorEmbeddings: [Int: [Float]] = [:]
        var filled: Set<Int> = []
        var completed = false

        for await analysis in session.stream {
            guard let sample = analysis.sample else {
                setEnrollment(filled, Self.hint(for: analysis.status))
                continue
            }
            if let image = sample.preview { preview = image }
            liveness.ingest(sample)
            guard let embedding = sample.embedding else {
                setEnrollment(filled, "Hold still and improve lighting")
                continue
            }

            if baseline.count < 8 {
                baseline.append((sample.turnX, sample.turnY))
                if baseline.count.isMultiple(of: 2) { centerEmbeddings.append(embedding) }
                setEnrollment(filled, "Hold still…")
                continue
            }

            let baseX = baseline.map(\.x).reduce(0, +) / Double(baseline.count)
            let baseY = baseline.map(\.y).reduce(0, +) / Double(baseline.count)
            let dx = sample.turnX - baseX
            let dy = (sample.turnY - baseY) * 1.6
            if hypot(dx, dy) >= PoseSectors.activationDistance {
                let sector = PoseSectors.sector(forDegrees: atan2(dy, -dx) * 180 / .pi)
                if filled.insert(sector).inserted { sectorEmbeddings[sector] = embedding }
            }

            if filled.count >= PoseSectors.requiredToFinish {
                let result = liveness.evaluate()
                if result.passed {
                    completed = true
                    break
                }
                setEnrollment(filled, result.hint)
            } else {
                setEnrollment(filled, filled.isEmpty ? "Slowly move your head in a circle" : "Keep moving your head in a circle")
            }
        }
        closeSession()

        guard completed else { return await finish(false, "Setup timed out. Try again.") }
        let embeddings = centerEmbeddings + sectorEmbeddings.keys.sorted().compactMap { sectorEmbeddings[$0] }
        store.save(.make(embedderID: embedder.identifier, embeddings: embeddings, thresholdRange: embedder.thresholdRange))
        reloadTemplate()
        return await finish(isEnrolled, isEnrolled ? "Face ID is set up" : "Could not save face data")
    }

    // MARK: - Authentication

    /// `preempt` stops any other face operation first (the lock screen takes priority).
    /// `onVerified` runs while the success animation is showing, before the result is returned.
    @discardableResult
    func authenticate(
        strict: Bool? = nil,
        timeout: Duration = .seconds(7),
        preempt: Bool = false,
        onVerified: () async -> Void = {}
    ) async -> Bool {
        guard await begin("authenticate", preempt: preempt) else { return false }
        defer { end() }
        phase = .scanning(hint: "")
        guard let template else { return await finish(false, "Set up Face ID first") }
        guard let session = await openSession(timeout: timeout, options: .recognition) else {
            return await finish(false, cameraError ?? "No camera available")
        }

        let verifier = Verifier(template: template, liveness: LivenessDetector(requireBlink: strict ?? settings.requireBlink))
        var outcome = Verifier.Outcome.searching
        for await analysis in session.stream {
            guard let sample = analysis.sample else { continue }
            outcome = verifier.ingest(sample)
            lastScore = verifier.score
            if outcome == .verified { break }
            if case .matched(let hint) = outcome, phase != .scanning(hint: hint) {
                phase = .scanning(hint: hint)
            }
        }
        closeSession()

        switch outcome {
        case .verified:
            phase = .success("Unlocked")
            await onVerified()
            return await finish(true, "Unlocked")
        case .matched(let hint): return await finish(false, hint.isEmpty ? "Liveness check failed" : hint)
        case .searching: return await finish(false, "Face Not Recognized")
        }
    }

    /// Verifies the owner, then waits for a gesture and runs the matching action.
    func faceCommand(_ actions: [FaceAction], perform: (FaceAction) -> Void) async {
        guard await begin("gesture command") else { return }
        defer { end() }
        phase = .scanning(hint: "")
        guard !actions.isEmpty else { _ = await finish(false, "No gestures configured"); return }
        guard let template else { _ = await finish(false, "Set up Face ID first"); return }
        guard let session = await openSession(timeout: .seconds(10), options: .recognition) else {
            _ = await finish(false, cameraError ?? "No camera available")
            return
        }

        let verifier = Verifier(template: template, liveness: LivenessDetector(requireBlink: false))
        let gestures = GestureDetector()
        let hint = actions.prefix(3).map(\.gesture.title).joined(separator: " · ")
        var recognized = false
        var chosen: FaceAction?

        for await analysis in session.stream {
            guard let sample = analysis.sample else { continue }
            if !recognized {
                _ = verifier.ingest(sample)
                lastScore = verifier.score
                if verifier.isMatched {
                    recognized = true
                    phase = .scanning(hint: hint)
                }
            } else if let gesture = gestures.ingest(sample), let action = actions.first(where: { $0.gesture == gesture }) {
                chosen = action
                break
            }
        }
        closeSession()

        if let chosen {
            perform(chosen)
            _ = await finish(true, chosen.summary)
        } else {
            _ = await finish(false, recognized ? "No gesture detected" : "Face Not Recognized")
        }
    }

    /// Cheap face-presence watch (rectangles only, 5 fps), used on the lock screen so it preempts other operations.
    /// Returns nil if the camera is unavailable or busy.
    func waitFor(_ goal: PresenceGoal, timeout: Duration) async -> Bool? {
        guard await begin("presence", preempt: true) else { return nil }
        defer { end() }
        guard let session = await openSession(timeout: timeout, options: .presence, maxFPS: Self.presenceFPS) else { return nil }

        var lastFaceAt = ProcessInfo.processInfo.systemUptime
        for await analysis in session.stream {
            let now = ProcessInfo.processInfo.systemUptime
            let hasFace = analysis.status != .noFace
            switch goal {
            case .faceAppears:
                if hasFace { return true }
            case .faceAbsent(let seconds):
                if hasFace { lastFaceAt = now } else if now - lastFaceAt >= seconds { return true }
            }
        }
        return false
    }

    // MARK: - Live monitor

    func startMonitor() {
        guard !isMonitoring, !operationInProgress else { return }
        isMonitoring = true
        liveStats = LiveStats()
        monitorTask = Task { await runMonitor() }
    }

    func stopMonitor() {
        guard isMonitoring else { return }
        monitorTask?.cancel()
        monitorTask = nil
        closeSession()
        isMonitoring = false
        liveFrame = nil
    }

    private func runMonitor() async {
        guard let session = await openSession(timeout: .seconds(900), options: AnalyzerOptions(fullFrame: true)) else {
            liveStats.status = cameraError ?? "No camera available"
            isMonitoring = false
            return
        }
        let liveness = LivenessDetector(requireBlink: settings.requireBlink)
        let gestures = GestureDetector()
        var frameCount = 0
        var windowStart = ProcessInfo.processInfo.systemUptime

        for await analysis in session.stream {
            guard !Task.isCancelled else { break }
            liveFrame = analysis.frame
            var stats = liveStats
            frameCount += 1
            let now = ProcessInfo.processInfo.systemUptime
            if now - windowStart >= 1 {
                stats.fps = Double(frameCount) / (now - windowStart)
                frameCount = 0
                windowStart = now
            }
            stats.faceRect = analysis.faceRect
            switch analysis.status {
            case .noFace: stats.status = "No face"
            case .tooFar: stats.status = "Too far — move closer"
            case .present: stats.status = "Face (no landmarks)"
            case .face: stats.status = "Face detected"
            }
            if let sample = analysis.sample {
                liveness.ingest(sample)
                if let gesture = gestures.ingest(sample) { stats.lastGesture = gesture }
                stats.quality = sample.quality
                stats.eyeOpenness = sample.eyeOpenness
                stats.turnX = sample.turnX
                stats.turnY = sample.turnY
                stats.blinks = liveness.blinkCount
                if let embedding = sample.embedding, let template { stats.score = template.score(embedding) }
                let result = liveness.evaluate()
                stats.liveness = result.passed ? "Live ✓" : result.hint
            }
            liveStats = stats
        }
        if activeSession === session {
            closeSession()
            isMonitoring = false
            liveFrame = nil
        }
    }

    // MARK: - Demo

    func runDemo() async {
        guard await begin("demo") else { return }
        defer { end() }
        phase = .scanning(hint: "")
        try? await Task.sleep(for: .seconds(1.6))
        _ = await finish(true, "Unlocked")
        try? await Task.sleep(for: .seconds(0.9))

        phase = .scanning(hint: "")
        try? await Task.sleep(for: .seconds(1.4))
        _ = await finish(false, "Face Not Recognized")
        try? await Task.sleep(for: .seconds(0.9))

        var filled: Set<Int> = []
        phase = .enrolling(filled: filled, hint: "Slowly move your head in a circle")
        for sector in 0..<PoseSectors.count {
            try? await Task.sleep(for: .seconds(0.45))
            filled.insert(sector)
            phase = .enrolling(filled: filled, hint: "Keep moving your head in a circle")
        }
        try? await Task.sleep(for: .seconds(0.5))
        _ = await finish(true, "Face ID is set up")
    }

    // MARK: - Helpers

    private func begin(_ name: String, preempt: Bool = false) async -> Bool {
        if operationInProgress, preempt {
            Log.unlock.notice("Stopping \(self.currentOperation, privacy: .public) to start \(name, privacy: .public)")
            closeSession()
            var waited = 0
            while operationInProgress, waited < 40 {
                try? await Task.sleep(for: .milliseconds(100))
                waited += 1
            }
        }
        guard !operationInProgress else {
            Log.app.error("Can't start \(name, privacy: .public): \(self.currentOperation, privacy: .public) is running")
            return false
        }
        stopMonitor()
        operationInProgress = true
        currentOperation = name
        isLockScreenOperation = preempt
        dismissRequested = false
        return true
    }

    /// Ends a lock-screen scan right away and closes the notch without a failure animation
    /// (the user unlocked the Mac another way).
    func dismissLockScreenOperation() {
        guard operationInProgress, isLockScreenOperation else { return }
        dismissRequested = true
        closeSession()
        preview = nil
        phase = .idle
    }

    private func end() {
        closeSession()
        operationInProgress = false
        currentOperation = ""
    }

    private func openSession(timeout: Duration, options: AnalyzerOptions, maxFPS: Double = recognitionFPS) async -> FrameSession? {
        guard await CameraService.requestAccess() else {
            cameraError = "Camera access denied. Allow it in System Settings → Privacy & Security → Camera."
            return nil
        }
        closeSession()
        do {
            let analyzer = FaceAnalyzer(embedder: embedder, spoofClassifier: spoofClassifier, options: options)
            let session = try FrameSession(camera: camera, analyzer: analyzer, timeout: timeout, maxFPS: maxFPS)
            activeSession = session
            cameraError = nil
            return session
        } catch {
            cameraError = "No camera available"
            return nil
        }
    }

    private func closeSession() {
        activeSession?.stop()
        activeSession = nil
    }

    private func reloadTemplate() {
        let stored = store.load()
        template = stored?.embedderID == embedder.identifier ? stored : nil
        isEnrolled = template != nil
    }

    private func setEnrollment(_ filled: Set<Int>, _ hint: String) {
        let next = AuthPhase.enrolling(filled: filled, hint: hint)
        if phase != next { phase = next }
    }

    private func finish(_ success: Bool, _ message: String) async -> Bool {
        closeSession()
        preview = nil
        if !success, dismissRequested || Task.isCancelled {
            phase = .idle
            return false
        }
        phase = success ? .success(message) : .failure(message)
        try? await Task.sleep(for: .seconds(success ? 1.1 : 1.6))
        phase = .idle
        return success
    }

    private static func hint(for status: FaceAnalysis.Status) -> String {
        switch status {
        case .noFace: return "Looking for your face…"
        case .tooFar: return "Move closer"
        case .present, .face: return "Hold still…"
        }
    }
}
