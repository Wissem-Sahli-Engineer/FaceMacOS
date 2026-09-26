import Accelerate
import CoreML
import Vision

enum EmbeddingError: Error {
    case noOutput
}

protocol FaceEmbedder: AnyObject {
    var identifier: String { get }
    var displayName: String { get }
    var isDevelopmentFallback: Bool { get }
    /// Bounds for the per-user match threshold calibrated at enrollment (cosine similarity).
    var thresholdRange: ClosedRange<Float> { get }
    func embedding(for face: CGImage) throws -> [Float]
}

enum Embedders {
    static func best() -> FaceEmbedder {
        CoreMLFaceEmbedder(resource: "FaceEmbedding") ?? FeaturePrintEmbedder()
    }
}

/// Face-specific embedding model (e.g. FaceNet/VGGFace2) bundled as FaceEmbedding.mlmodelc.
final class CoreMLFaceEmbedder: FaceEmbedder {
    let identifier: String
    let displayName = "Core ML face embedding"
    let isDevelopmentFallback = false
    let thresholdRange: ClosedRange<Float> = 0.45...0.70
    private let request: VNCoreMLRequest

    init?(resource: String) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "mlmodelc") else { return nil }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        guard let model = try? MLModel(contentsOf: url, configuration: configuration),
              let visionModel = try? VNCoreMLModel(for: model)
        else { return nil }
        let version = model.modelDescription.metadata[.versionString] as? String ?? "1"
        identifier = "coreml:\(resource):\(version)"
        request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill
    }

    func embedding(for face: CGImage) throws -> [Float] {
        try VNImageRequestHandler(cgImage: face).perform([request])
        guard let observation = request.results?.first as? VNCoreMLFeatureValueObservation,
              let array = observation.featureValue.multiArrayValue
        else { throw EmbeddingError.noOutput }
        let values = (0..<array.count).map { array[$0].floatValue }
        return VectorMath.normalized(values)
    }
}

/// Generic Vision image feature print. Not trained for identity: only a stand-in until a real model is installed.
final class FeaturePrintEmbedder: FaceEmbedder {
    let identifier = "vision:featureprint:v1"
    let displayName = "Vision feature print (dev fallback)"
    let isDevelopmentFallback = true
    let thresholdRange: ClosedRange<Float> = 0.75...0.97
    private let request: VNGenerateImageFeaturePrintRequest = {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFill
        return request
    }()

    func embedding(for face: CGImage) throws -> [Float] {
        try VNImageRequestHandler(cgImage: face).perform([request])
        guard let print = request.results?.first else { throw EmbeddingError.noOutput }
        let values: [Float] = print.data.withUnsafeBytes { raw in
            switch print.elementType {
            case .double: return raw.bindMemory(to: Double.self).map(Float.init)
            default: return Array(raw.bindMemory(to: Float.self))
            }
        }
        return VectorMath.normalized(values)
    }
}

enum VectorMath {
    static func normalized(_ v: [Float]) -> [Float] {
        var sumSquares: Float = 0
        vDSP_svesq(v, 1, &sumSquares, vDSP_Length(v.count))
        let norm = sumSquares.squareRoot()
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }

    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }
}
