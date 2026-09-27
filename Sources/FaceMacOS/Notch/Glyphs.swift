import SwiftUI

extension StrokeStyle {
    static let glyph = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
}

/// The Face ID mark: four corner brackets, eyes, nose and smile.
struct FaceIDGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - s / 2, y: rect.midY - s / 2)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * s, y: origin.y + y * s) }
        let arm: CGFloat = 0.26
        let r: CGFloat = 0.16

        var path = Path()
        path.move(to: p(0, arm)); path.addLine(to: p(0, r)); path.addQuadCurve(to: p(r, 0), control: p(0, 0)); path.addLine(to: p(arm, 0))
        path.move(to: p(1 - arm, 0)); path.addLine(to: p(1 - r, 0)); path.addQuadCurve(to: p(1, r), control: p(1, 0)); path.addLine(to: p(1, arm))
        path.move(to: p(1, 1 - arm)); path.addLine(to: p(1, 1 - r)); path.addQuadCurve(to: p(1 - r, 1), control: p(1, 1)); path.addLine(to: p(1 - arm, 1))
        path.move(to: p(arm, 1)); path.addLine(to: p(r, 1)); path.addQuadCurve(to: p(0, 1 - r), control: p(0, 1)); path.addLine(to: p(0, 1 - arm))

        path.move(to: p(0.33, 0.33)); path.addLine(to: p(0.33, 0.42))
        path.move(to: p(0.67, 0.33)); path.addLine(to: p(0.67, 0.42))
        path.move(to: p(0.5, 0.33)); path.addLine(to: p(0.5, 0.57)); path.addLine(to: p(0.44, 0.57))
        path.move(to: p(0.33, 0.70)); path.addQuadCurve(to: p(0.67, 0.70), control: p(0.5, 0.80))
        return path
    }
}

struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.76))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.28))
        return path
    }
}

struct ScanningGlyph: View {
    let accent: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: 0.2)
                    .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.radians(t * 2 * .pi * 0.9))
                FaceIDGlyph()
                    .stroke(Color.white, style: .glyph)
                    .padding(18)
                    .scaleEffect(0.96 + 0.04 * sin(t * 6))
            }
        }
    }
}

struct SuccessGlyph: View {
    let color: Color
    @State private var progress: CGFloat = 0

    var body: some View {
        CheckmarkShape()
            .trim(from: 0, to: progress)
            .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            .padding(12)
            .onAppear {
                withAnimation(.easeOut(duration: 0.35).delay(0.05)) { progress = 1 }
            }
    }
}

/// Face ID-style enrollment: live mirrored face inside a ring of ticks that light up per head-pose sector.
struct EnrollmentRing: View {
    let filled: Set<Int>
    let preview: CGImage?
    let accent: Color
    private static let tickCount = 72

    var body: some View {
        GeometryReader { geometry in
            let d = min(geometry.size.width, geometry.size.height)
            ZStack {
                Group {
                    if let preview {
                        Image(decorative: preview, scale: 1).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color.white.opacity(0.06)
                            FaceIDGlyph().stroke(Color.white.opacity(0.5), style: .glyph).padding(d * 0.2)
                        }
                    }
                }
                .frame(width: d * 0.74, height: d * 0.74)
                .clipShape(Circle())

                ForEach(0..<Self.tickCount, id: \.self) { index in
                    let degrees = Double(index) * 360 / Double(Self.tickCount)
                    Capsule()
                        .fill(filled.contains(PoseSectors.sector(forDegrees: 90 - degrees)) ? accent : Color.white.opacity(0.25))
                        .frame(width: 3, height: d * 0.075)
                        .offset(y: -(d / 2 - d * 0.05))
                        .rotationEffect(.degrees(degrees))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(.easeOut(duration: 0.25), value: filled)
        }
    }
}
