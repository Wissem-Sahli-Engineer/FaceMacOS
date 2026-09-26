import CoreML
import Vision

/// Optional real-vs-spoof image classifier bundled as LivenessClassifier.mlmodelc,
/// with class labels "real" and "spoof" (e.g. trained in Create ML on face crops).
final class SpoofClassifier {
    private let request: VNCoreMLRequest

    static func load() -> SpoofClassifier? {
        guard let url = Bundle.main.url(forResource: "LivenessClassifier", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: url),
              let visionModel = try? VNCoreMLModel(for: model)
        else { return nil }
        return SpoofClassifier(model: visionModel)
    }

    private init(model: VNCoreMLModel) {
        request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
    }

    func realProbability(for face: CGImage) -> Float? {
        guard (try? VNImageRequestHandler(cgImage: face).perform([request])) != nil,
              let results = request.results as? [VNClassificationObservation],
              let real = results.first(where: { $0.identifier.lowercased() == "real" })
        else { return nil }
        return real.confidence
    }
}
