import Foundation

struct FaceTemplate: Codable {
    var embedderID: String
    var embeddings: [[Float]]
    var threshold: Float
    var createdAt: Date

    /// Mean of the 3 best cosine similarities against the enrolled poses.
    func score(_ embedding: [Float]) -> Float {
        let best = embeddings.map { VectorMath.dot($0, embedding) }.sorted(by: >).prefix(3)
        guard !best.isEmpty else { return 0 }
        return best.reduce(0, +) / Float(best.count)
    }

    static func make(embedderID: String, embeddings: [[Float]], thresholdRange: ClosedRange<Float>) -> FaceTemplate {
        var similarities: [Float] = []
        for i in embeddings.indices {
            for j in embeddings.indices where j > i {
                similarities.append(VectorMath.dot(embeddings[i], embeddings[j]))
            }
        }
        let mean = similarities.isEmpty ? thresholdRange.upperBound : similarities.reduce(0, +) / Float(similarities.count)
        let variance = similarities.isEmpty ? 0 : similarities.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(similarities.count)
        let calibrated = mean - 2.5 * variance.squareRoot()
        let threshold = min(max(calibrated, thresholdRange.lowerBound), thresholdRange.upperBound)
        return FaceTemplate(embedderID: embedderID, embeddings: embeddings, threshold: threshold, createdAt: Date())
    }
}

struct FaceStore {
    func load() -> FaceTemplate? {
        guard let data = Secrets.load()?.faceTemplate else { return nil }
        return try? JSONDecoder().decode(FaceTemplate.self, from: data)
    }

    func save(_ template: FaceTemplate) {
        guard let data = try? JSONEncoder().encode(template) else { return }
        Secrets.update { $0.faceTemplate = data }
    }

    func delete() {
        Secrets.update { $0.faceTemplate = nil }
    }
}
