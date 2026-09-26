import Foundation

struct LivenessResult {
    let passed: Bool
    let hint: String
}

/// Detects blinks relative to a rolling "eyes open" level, so it adapts to each person and lighting.
final class BlinkTracker {
    private var history: [(time: TimeInterval, value: Double)] = []
    private var closedAt: TimeInterval?
    private var waitingForOpen = false

    /// Returns true on the frame where a completed blink is detected.
    func ingest(openness: Double, at time: TimeInterval) -> Bool {
        guard openness > 0 else { return false }
        history.append((time, openness))
        history.removeAll { time - $0.time > 2.0 }
        guard history.count >= 5 else { return false }

        let sorted = history.map(\.value).sorted()
        let openLevel = sorted[Int(Double(sorted.count - 1) * 0.8)]

        if waitingForOpen {
            if openness > openLevel * 0.85 { waitingForOpen = false }
            return false
        }
        if let start = closedAt {
            if openness > openLevel * 0.85 {
                closedAt = nil
                return time - start <= 0.8
            }
            if time - start > 1.0 {
                closedAt = nil
                waitingForOpen = true
            }
        } else if openness < openLevel * 0.72 {
            closedAt = time
        }
        return false
    }
}

/// Combines blink, micro-motion, frozen-frame and (optional) ML spoof signals.
/// RGB-only liveness raises the bar against printed/screen photos but is not TrueDepth-grade.
final class LivenessDetector {
    static let staticFrameThreshold = 0.0015
    static let minimumHeadMotion = 0.03
    static let minimumRealProbability: Float = 0.6

    let requireBlink: Bool
    private(set) var blinkCount = 0
    private let blinks = BlinkTracker()
    private var turnXs: [Double] = []
    private var frameDiffs: [Double] = []
    private var lastSignature: [Float]?
    private var realScores: [Float] = []

    init(requireBlink: Bool) {
        self.requireBlink = requireBlink
    }

    func ingest(_ sample: FaceSample) {
        if blinks.ingest(openness: sample.eyeOpenness, at: sample.timestamp) { blinkCount += 1 }
        turnXs.append(sample.turnX)
        if let last = lastSignature, last.count == sample.signature.count {
            let diff = zip(last, sample.signature).reduce(0) { $0 + abs(Double($1.0 - $1.1)) }
            frameDiffs.append(diff / Double(last.count))
        }
        lastSignature = sample.signature
        if let real = sample.realProbability { realScores.append(real) }
    }

    func evaluate() -> LivenessResult {
        if realScores.count >= 5 {
            let mean = realScores.reduce(0, +) / Float(realScores.count)
            if mean < Self.minimumRealProbability { return LivenessResult(passed: false, hint: "Real face required") }
        }
        if isStatic { return LivenessResult(passed: false, hint: "Move slightly") }
        if blinkCount > 0 { return LivenessResult(passed: true, hint: "") }
        if requireBlink { return LivenessResult(passed: false, hint: "Blink to confirm") }
        if headMotion >= Self.minimumHeadMotion { return LivenessResult(passed: true, hint: "") }
        return LivenessResult(passed: false, hint: "Move your head slightly")
    }

    private var isStatic: Bool {
        guard frameDiffs.count >= 8 else { return false }
        let sorted = frameDiffs.sorted()
        return sorted[sorted.count / 2] < Self.staticFrameThreshold
    }

    private var headMotion: Double {
        (turnXs.max() ?? 0) - (turnXs.min() ?? 0)
    }
}

/// Turns a stream of face samples into discrete gestures (blink patterns, head turns).
final class GestureDetector {
    static let turnThreshold = 0.22
    static let tiltThreshold = 0.14
    static let blinkSequenceGap = 0.7
    static let holdFrames = 3

    private let blinks = BlinkTracker()
    private var blinkTimes: [TimeInterval] = []
    private var baseline: [(x: Double, y: Double)] = []
    private var poseStreak: (gesture: FaceGesture, frames: Int)?

    func ingest(_ sample: FaceSample) -> FaceGesture? {
        if baseline.count < 6 {
            baseline.append((sample.turnX, sample.turnY))
            return nil
        }
        let dx = sample.turnX - baseline.map(\.x).reduce(0, +) / Double(baseline.count)
        let dy = sample.turnY - baseline.map(\.y).reduce(0, +) / Double(baseline.count)

        var pose: FaceGesture?
        if abs(dx) >= Self.turnThreshold, abs(dx) > abs(dy) {
            // Camera frames are not mirrored: turning to your left moves the nose toward image-right.
            pose = dx > 0 ? .lookLeft : .lookRight
        } else if abs(dy) >= Self.tiltThreshold {
            pose = dy > 0 ? .lookUp : .lookDown
        }

        if let pose {
            let frames = poseStreak?.gesture == pose ? (poseStreak?.frames ?? 0) + 1 : 1
            poseStreak = (pose, frames)
            blinkTimes.removeAll()
            return frames == Self.holdFrames ? pose : nil
        }
        poseStreak = nil

        if blinks.ingest(openness: sample.eyeOpenness, at: sample.timestamp) {
            blinkTimes.append(sample.timestamp)
        }
        guard let last = blinkTimes.last, sample.timestamp - last > Self.blinkSequenceGap else { return nil }
        defer { blinkTimes.removeAll() }
        switch blinkTimes.count {
        case 2: return .doubleBlink
        case 3...: return .tripleBlink
        default: return nil
        }
    }
}
