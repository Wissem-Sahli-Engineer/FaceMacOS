import SwiftUI

struct LiveCameraView: View {
    @ObservedObject var auth: FaceAuthenticator

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            cameraPanel
            statsPanel.frame(width: 240)
        }
        .padding(20)
        .navigationTitle("Live Camera")
        .toolbar {
            Button(auth.isMonitoring ? "Stop Camera" : "Start Camera") {
                auth.isMonitoring ? auth.stopMonitor() : auth.startMonitor()
            }
            .disabled(auth.isBusy)
        }
        .onAppear { auth.startMonitor() }
        .onDisappear { auth.stopMonitor() }
    }

    private var cameraPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color.black)
            if let frame = auth.liveFrame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay {
                        GeometryReader { geometry in
                            if let rect = auth.liveStats.faceRect {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.green, lineWidth: 2)
                                    .frame(width: rect.width * geometry.size.width, height: rect.height * geometry.size.height)
                                    .position(x: rect.midX * geometry.size.width, y: (1 - rect.midY) * geometry.size.height)
                            }
                        }
                    }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: auth.isMonitoring ? "video" : "video.slash").font(.largeTitle)
                    Text(auth.isBusy ? "Camera in use by Face ID" : auth.isMonitoring ? "Starting camera…" : "Camera off")
                }
                .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
    }

    private var statsPanel: some View {
        let stats = auth.liveStats
        return VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics").font(.headline)
            StatRow(label: "Status", value: stats.status)
            StatRow(label: "Frame rate", value: String(format: "%.0f fps", stats.fps))
            VStack(alignment: .leading, spacing: 4) {
                StatRow(label: "Image quality", value: String(format: "%.2f", stats.quality))
                ProgressView(value: Double(min(max(stats.quality, 0), 1)))
                    .tint(stats.quality >= FaceAnalyzer.minimumQuality ? .green : .orange)
            }
            if let score = stats.score {
                let passing = auth.threshold.map { score >= $0 } ?? false
                StatRow(label: "Match", value: String(format: "%.3f / %.3f", score, auth.threshold ?? 0), color: passing ? .green : .red)
            } else {
                StatRow(label: "Match", value: auth.isEnrolled ? "—" : "Not enrolled")
            }
            StatRow(label: "Eye openness", value: String(format: "%.3f", stats.eyeOpenness))
            StatRow(label: "Blinks", value: "\(stats.blinks)")
            StatRow(label: "Head turn", value: String(format: "x %.2f  y %.2f", stats.turnX, stats.turnY))
            StatRow(label: "Liveness", value: stats.liveness, color: stats.liveness.hasSuffix("✓") ? .green : .primary)
            StatRow(label: "Last gesture", value: stats.lastGesture?.title ?? "—")
            Spacer()
            Text("Use this view to check lighting and distance. Blink and turn your head to see blinks and gestures register.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(color).lineLimit(1)
        }
        .font(.callout)
    }
}
