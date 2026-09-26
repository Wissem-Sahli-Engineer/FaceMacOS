import CoreImage
import Vision

struct FaceSample {
    let timestamp: TimeInterval
    let quality: Float
    /// Nose offset from the eye midpoint along the eye axis, in inter-eye units (left/right head turn).
    let turnX: Double
    /// Nose offset perpendicular to the eye axis, in inter-eye units (up/down head tilt).
    let turnY: Double
    /// Eye height / eye width averaged over both eyes; drops sharply during a blink.
    let eyeOpenness: Double
    let embedding: [Float]?
    let realProbability: Float?
    /// 16x16 grayscale thumbnail of the aligned face, used to spot frozen frames.
    let signature: [Float]
    let preview: CGImage?
}

struct FaceAnalysis {
    enum Status { case noFace, tooFar, present, face }

    var status: Status
    var sample: FaceSample?
    var frame: CGImage?
    /// Normalized (Vision, bottom-left origin) and mirrored to match `frame`.
    var faceRect: CGRect?
}

struct AnalyzerOptions {
    var presenceOnly = false
    var facePreview = false
    var fullFrame = false

    static let presence = AnalyzerOptions(presenceOnly: true)
    static let recognition = AnalyzerOptions()
}

final class FaceAnalyzer {
    static let minimumQuality: Float = 0.2
    static let minimumFaceWidth: CGFloat = 0.12
    static let embeddingInputSize: CGFloat = 160

    private let embedder: FaceEmbedder
    private let spoofClassifier: SpoofClassifier?
    private let options: AnalyzerOptions
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let rectanglesRequest = VNDetectFaceRectanglesRequest()
    private let landmarksRequest: VNDetectFaceLandmarksRequest = {
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        request.constellation = .constellation76Points
        return request
    }()
    private let qualityRequest = VNDetectFaceCaptureQualityRequest()

    init(embedder: FaceEmbedder, spoofClassifier: SpoofClassifier?, options: AnalyzerOptions) {
        self.embedder = embedder
        self.spoofClassifier = spoofClassifier
        self.options = options
    }

    func analyze(_ buffer: CVPixelBuffer) -> FaceAnalysis {
        let image = CIImage(cvPixelBuffer: buffer)
        let frame = options.fullFrame ? renderFullFrame(image) : nil
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)

        if options.presenceOnly {
            guard (try? handler.perform([rectanglesRequest])) != nil,
                  let face = rectanglesRequest.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width })
            else { return FaceAnalysis(status: .noFace, frame: frame) }
            return FaceAnalysis(status: .present, frame: frame, faceRect: mirrored(face.boundingBox))
        }

        guard (try? handler.perform([landmarksRequest])) != nil,
              let face = landmarksRequest.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width })
        else { return FaceAnalysis(status: .noFace, frame: frame) }
        let faceRect = mirrored(face.boundingBox)
        guard face.boundingBox.width >= Self.minimumFaceWidth else {
            return FaceAnalysis(status: .tooFar, frame: frame, faceRect: faceRect)
        }
        guard let landmarks = face.landmarks,
              let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye,
              let nose = landmarks.nose
        else { return FaceAnalysis(status: .present, frame: frame, faceRect: faceRect) }

        let size = image.extent.size
        let eyeA = leftEye.pointsInImage(imageSize: size)
        let eyeB = rightEye.pointsInImage(imageSize: size)
        var c1 = centroid(eyeA)
        var c2 = centroid(eyeB)
        if c1.x > c2.x { swap(&c1, &c2) }

        let interEye = hypot(c2.x - c1.x, c2.y - c1.y)
        guard interEye > 1 else { return FaceAnalysis(status: .present, frame: frame, faceRect: faceRect) }
        let u = CGVector(dx: (c2.x - c1.x) / interEye, dy: (c2.y - c1.y) / interEye)
        let v = CGVector(dx: -u.dy, dy: u.dx)
        let mid = CGPoint(x: (c1.x + c2.x) / 2, y: (c1.y + c2.y) / 2)
        let noseCenter = centroid(nose.pointsInImage(imageSize: size))
        let d = CGVector(dx: noseCenter.x - mid.x, dy: noseCenter.y - mid.y)
        let turnX = Double((d.dx * u.dx + d.dy * u.dy) / interEye)
        let turnY = Double((d.dx * v.dx + d.dy * v.dy) / interEye)
        let openness = (eyeAspect(eyeA, u: u, v: v) + eyeAspect(eyeB, u: u, v: v)) / 2

        qualityRequest.inputFaceObservations = [face]
        try? handler.perform([qualityRequest])
        let quality = qualityRequest.results?.first?.faceCaptureQuality ?? 0

        let box = VNImageRectForNormalizedRect(face.boundingBox, Int(size.width), Int(size.height))
        let center = CGPoint(x: box.midX, y: box.midY)
        let side = max(box.width, box.height) * 1.2
        guard let crop = render(image, center: center, side: side, angle: atan2(u.dy, u.dx), output: Self.embeddingInputSize, mirrored: false)
        else { return FaceAnalysis(status: .present, frame: frame, faceRect: faceRect) }

        let usable = quality >= Self.minimumQuality
        let sample = FaceSample(
            timestamp: ProcessInfo.processInfo.systemUptime,
            quality: quality,
            turnX: turnX,
            turnY: turnY,
            eyeOpenness: openness,
            embedding: usable ? try? embedder.embedding(for: crop) : nil,
            realProbability: usable ? spoofClassifier?.realProbability(for: crop) : nil,
            signature: signature(of: crop),
            preview: options.facePreview
                ? render(image, center: center, side: side * 1.5, angle: 0, output: 240, mirrored: true)
                : nil
        )
        return FaceAnalysis(status: .face, sample: sample, frame: frame, faceRect: faceRect)
    }

    private func mirrored(_ rect: CGRect) -> CGRect {
        CGRect(x: 1 - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
    }

    private func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private func eyeAspect(_ points: [CGPoint], u: CGVector, v: CGVector) -> Double {
        let along = points.map { $0.x * u.dx + $0.y * u.dy }
        let across = points.map { $0.x * v.dx + $0.y * v.dy }
        guard let aMin = along.min(), let aMax = along.max(), let cMin = across.min(), let cMax = across.max(),
              aMax - aMin > 0 else { return 0 }
        return Double((cMax - cMin) / (aMax - aMin))
    }

    private func render(_ image: CIImage, center: CGPoint, side: CGFloat, angle: CGFloat, output: CGFloat, mirrored: Bool) -> CGImage? {
        let scale = output / side
        let transform = CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(CGAffineTransform(rotationAngle: -angle))
            .concatenating(CGAffineTransform(scaleX: mirrored ? -scale : scale, y: scale))
            .concatenating(CGAffineTransform(translationX: output / 2, y: output / 2))
        let rect = CGRect(x: 0, y: 0, width: output, height: output)
        let result = image.clampedToExtent().transformed(by: transform).cropped(to: rect)
        return context.createCGImage(result, from: rect)
    }

    private func renderFullFrame(_ image: CIImage) -> CGImage? {
        let width: CGFloat = 640
        let scale = width / image.extent.width
        let transform = CGAffineTransform(scaleX: -scale, y: scale).concatenating(CGAffineTransform(translationX: width, y: 0))
        return context.createCGImage(image.transformed(by: transform), from: CGRect(x: 0, y: 0, width: width, height: image.extent.height * scale))
    }

    private func signature(of image: CGImage) -> [Float] {
        let n = 16
        var pixels = [UInt8](repeating: 0, count: n * n)
        pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        }
        return pixels.map { Float($0) / 255 }
    }
}
