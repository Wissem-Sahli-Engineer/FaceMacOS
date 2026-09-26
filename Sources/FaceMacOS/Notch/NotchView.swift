import SwiftUI

struct NotchView: View {
    @ObservedObject var auth: FaceAuthenticator
    let closedSize: CGSize

    @State private var shown: AuthPhase = .idle
    @State private var isOpen = false
    @State private var contentVisible = false
    @State private var isVisible = false
    @State private var shakes: CGFloat = 0

    var body: some View {
        let flare: CGFloat = isOpen ? 14 : 6
        let size = isOpen ? Self.size(for: shown, closed: closedSize) : closedSize
        NotchShape(topRadius: flare, bottomRadius: isOpen ? 38 : 10)
            .fill(Color.black)
            .frame(width: size.width + flare * 2, height: size.height)
            .overlay(alignment: .top) {
                ZStack { content(for: shown) }
                    .id(Self.kind(of: shown))
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    .padding(.top, closedSize.height + 8)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .opacity(contentVisible ? 1 : 0)
                    .blur(radius: contentVisible ? 0 : 5)
                    .scaleEffect(contentVisible ? 1 : 0.92, anchor: .top)
            }
            .modifier(Shake(animatableData: shakes))
            .shadow(color: .black.opacity(isOpen ? 0.4 : 0), radius: 20, y: 10)
            .opacity(isVisible ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: auth.phase) { oldPhase, newPhase in
                transition(from: oldPhase, to: newPhase)
            }
    }

    private func transition(from oldPhase: AuthPhase, to newPhase: AuthPhase) {
        if newPhase == .idle {
            withAnimation(.easeOut(duration: 0.16)) { contentVisible = false }
            withAnimation(.smooth(duration: 0.55)) { isOpen = false }
            withAnimation(.easeIn(duration: 0.25).delay(0.4)) { isVisible = false }
            return
        }

        if oldPhase == .idle || !isOpen {
            shown = newPhase
            withAnimation(.easeOut(duration: 0.12)) { isVisible = true }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { isOpen = true }
            withAnimation(.easeOut(duration: 0.28).delay(0.1)) { contentVisible = true }
        } else if Self.kind(of: oldPhase) != Self.kind(of: newPhase) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { shown = newPhase }
        } else {
            shown = newPhase
        }

        if case .failure = newPhase {
            withAnimation(.linear(duration: 0.5)) { shakes += 1 }
        }
    }

    @ViewBuilder
    private func content(for phase: AuthPhase) -> some View {
        switch phase {
        case .idle:
            Color.clear
        case .scanning(let hint):
            VStack(spacing: 14) {
                ScanningGlyph().frame(width: 84, height: 84)
                label(hint.isEmpty ? "Face ID" : hint)
            }
        case .enrolling(let filled, let hint):
            VStack(spacing: 12) {
                EnrollmentRing(filled: filled, preview: auth.preview).frame(width: 220, height: 220)
                label(hint)
            }
        case .success(let message):
            VStack(spacing: 14) {
                SuccessGlyph().frame(width: 84, height: 84)
                label(message)
            }
        case .failure(let message):
            VStack(spacing: 14) {
                FaceIDGlyph()
                    .stroke(Color.white, style: .glyph)
                    .padding(16)
                    .frame(width: 84, height: 84)
                label(message, color: Color(red: 1, green: 0.38, blue: 0.36))
            }
        }
    }

    private func label(_ text: String, color: Color = .white) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 12)
    }

    private static func size(for phase: AuthPhase, closed: CGSize) -> CGSize {
        switch phase {
        case .idle: return closed
        case .enrolling: return CGSize(width: 290, height: closed.height + 280)
        case .failure: return CGSize(width: 250, height: closed.height + 150)
        default: return CGSize(width: 210, height: closed.height + 150)
        }
    }

    private static func kind(of phase: AuthPhase) -> Int {
        switch phase {
        case .idle: return 0
        case .scanning: return 1
        case .enrolling: return 2
        case .success: return 3
        case .failure: return 4
        }
    }
}

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius
        let b = max(0, min(bottomRadius, (rect.width - 2 * t) / 2, rect.height / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 9 * sin(animatableData * .pi * 6), y: 0))
    }
}
