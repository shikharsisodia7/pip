import SwiftUI
import PipKit

enum PipState {
    case idle, listening, speaking, confused, thinking, celebrating
}

/// Pip, a fuzzy little monster with two horns and a toothy grin. He levels up
/// as the child earns stars: 1 Sprout (orange), 2 Glow (aqua, glowing),
/// 3 Star (purple, star badge), 4 Crown (pink, golden crown).
struct PipView: View {
    @Environment(Session.self) private var session
    private let state: PipState
    private let size: CGFloat
    private let stageOverride: Int?

    @State private var bob = false
    @State private var blink = false

    init(state: PipState, size: CGFloat = 120, stage: Int? = nil) {
        self.state = state
        self.size = size
        self.stageOverride = stage
    }

    private var stage: Int { max(1, min(4, stageOverride ?? session.rewards.stage)) }

    private static let bodies: [[Color]] = [
        [Color(hex: 0xFFB45C), Color(hex: 0xF0782E)],
        [Color(hex: 0x6BE6D6), Color(hex: 0x1FA8B8)],
        [Color(hex: 0xB79BFF), Color(hex: 0x7550E0)],
        [Color(hex: 0xFF93C9), Color(hex: 0xE04E9A)],
    ]
    private var colors: [Color] { Self.bodies[stage - 1] }
    private var dark: Color { colors[1] }

    var body: some View {
        ZStack {
            if stage >= 2 {
                // A radial gradient instead of a blur: same soft glow, no
                // per-frame filter while Pip bobs.
                Circle()
                    .fill(RadialGradient(colors: [colors[0].opacity(0.55), colors[0].opacity(0)],
                                         center: .center, startRadius: size * 0.2, endRadius: size * 0.7))
                    .frame(width: size * 1.4, height: size * 1.4)
            }
            horns
            feet
            arms
            torso
            face
            if stage >= 3 {
                Image(systemName: "star.fill")
                    .font(.system(size: size * 0.15))
                    .foregroundStyle(Palette.sun)
                    .shadow(color: Palette.orange.opacity(0.6), radius: 3)
                    .offset(y: size * 0.3)
            }
            if stage >= 4 {
                crown.offset(y: -size * 0.5)
            }
            badge.offset(x: size * 0.46, y: -size * 0.42)
            if stage >= 2 { sparkles }
        }
        .frame(width: size * 1.25, height: size * 1.25)
        .rotationEffect(.degrees(state == .confused ? -7 : 0))
        .scaleEffect(state == .celebrating && bob ? 1.06 : 1)
        .offset(y: bob ? -size * 0.035 : size * 0.035)
        .animation(.easeInOut(duration: state == .celebrating ? 0.35 : 1.5).repeatForever(autoreverses: true), value: bob)
        .animation(.spring(response: 0.55, dampingFraction: 0.55), value: stage)
        .animation(.spring, value: state)
        .onAppear { bob = true }
        // Cancelled when Pip leaves the screen, so blink loops never pile up.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.5...4.5)))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.08)) { blink = true }
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.easeInOut(duration: 0.08)) { blink = false }
            }
        }
    }

    private var torso: some View {
        ZStack {
            Ellipse()
                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.92, height: size * 0.86)
            // Fuzzy spots
            Circle().fill(.white.opacity(0.18)).frame(width: size * 0.12).offset(x: -size * 0.28, y: size * 0.18)
            Circle().fill(.white.opacity(0.14)).frame(width: size * 0.08).offset(x: size * 0.3, y: size * 0.22)
            Circle().fill(.white.opacity(0.12)).frame(width: size * 0.06).offset(x: -size * 0.18, y: size * 0.32)
            // Shine
            Ellipse().fill(.white.opacity(0.28))
                .frame(width: size * 0.36, height: size * 0.16)
                .offset(x: -size * 0.16, y: -size * 0.3)
        }
        .overlay(Ellipse().stroke(.white.opacity(0.3), lineWidth: size * 0.015).frame(width: size * 0.92, height: size * 0.86))
        .shadow(color: dark.opacity(0.5), radius: size * 0.06, y: size * 0.04)
    }

    private var horns: some View {
        HStack(spacing: size * 0.34) {
            horn.rotationEffect(.degrees(-18))
            horn.rotationEffect(.degrees(18))
        }
        .offset(y: -size * 0.4)
    }

    private var horn: some View {
        Capsule()
            .fill(LinearGradient(colors: [Color(hex: 0xFFF1C9), Color(hex: 0xF5C76B)], startPoint: .top, endPoint: .bottom))
            .frame(width: size * 0.12, height: size * 0.22)
    }

    private var feet: some View {
        HStack(spacing: size * 0.22) {
            Capsule().fill(dark).frame(width: size * 0.22, height: size * 0.12)
            Capsule().fill(dark).frame(width: size * 0.22, height: size * 0.12)
        }
        .offset(y: size * 0.42)
    }

    private var arms: some View {
        let up = state == .celebrating
        return HStack(spacing: size * 0.78) {
            Capsule().fill(dark).frame(width: size * 0.12, height: size * 0.26)
                .rotationEffect(.degrees(up ? 140 : 25), anchor: .top)
            Capsule().fill(dark).frame(width: size * 0.12, height: size * 0.26)
                .rotationEffect(.degrees(up ? -140 : -25), anchor: .top)
        }
        .offset(y: size * 0.08)
    }

    private var face: some View {
        VStack(spacing: size * 0.04) {
            HStack(spacing: size * 0.1) { eye; eye }
            ZStack {
                HStack(spacing: size * 0.36) {
                    Ellipse().fill(Palette.pink.opacity(0.55)).frame(width: size * 0.12, height: size * 0.07)
                    Ellipse().fill(Palette.pink.opacity(0.55)).frame(width: size * 0.12, height: size * 0.07)
                }
                mouth
            }
        }
        .offset(y: -size * 0.04)
    }

    private var eye: some View {
        let big = state == .listening || state == .celebrating
        let w = size * (big ? 0.24 : 0.21)
        return ZStack {
            Ellipse().fill(.white).frame(width: w, height: w * 1.12)
            Circle().fill(Color(hex: 0x3A2A6B)).frame(width: w * 0.58)
                .offset(x: state == .thinking ? w * 0.12 : 0, y: state == .thinking ? -w * 0.18 : w * 0.06)
            Circle().fill(.white).frame(width: w * 0.2)
                .offset(x: -w * 0.1, y: -w * 0.08)
        }
        .scaleEffect(y: blink ? 0.1 : 1)
    }

    @ViewBuilder private var mouth: some View {
        switch state {
        case .speaking:
            Ellipse().fill(Color(hex: 0x5A1E3A))
                .frame(width: size * 0.16, height: size * (bob ? 0.12 : 0.05))
        case .confused:
            Capsule().fill(Color(hex: 0x5A1E3A)).frame(width: size * 0.13, height: size * 0.035).rotationEffect(.degrees(-12))
        case .thinking:
            Circle().fill(Color(hex: 0x5A1E3A)).frame(width: size * 0.06)
        default:
            ZStack(alignment: .top) {
                HalfCircle().fill(Color(hex: 0x5A1E3A))
                    .frame(width: size * (state == .celebrating ? 0.3 : 0.24), height: size * (state == .celebrating ? 0.15 : 0.11))
                Rectangle().fill(.white)
                    .frame(width: size * 0.05, height: size * 0.04)
                    .offset(x: size * 0.04)
            }
        }
    }

    private var crown: some View {
        Image(systemName: "crown.fill")
            .font(.system(size: size * 0.26))
            .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFE27A), Color(hex: 0xF5A623)], startPoint: .top, endPoint: .bottom))
            .shadow(color: Palette.orange.opacity(0.6), radius: 4)
    }

    private var sparkles: some View {
        ZStack {
            Image(systemName: "sparkle").offset(x: -size * 0.55, y: -size * 0.2)
            Image(systemName: "sparkle").font(.system(size: size * 0.08)).offset(x: size * 0.5, y: size * 0.25)
        }
        .font(.system(size: size * 0.12))
        .foregroundStyle(.white.opacity(0.85))
        .opacity(bob ? 1 : 0.4)
    }

    @ViewBuilder private var badge: some View {
        switch state {
        case .thinking: Image(systemName: "ellipsis.bubble.fill").font(.system(size: size * 0.2)).foregroundStyle(.white)
        case .confused: Image(systemName: "questionmark").font(.system(size: size * 0.22, weight: .heavy)).foregroundStyle(Palette.sun)
        case .listening: Image(systemName: "ear.fill").font(.system(size: size * 0.16)).foregroundStyle(Palette.mint)
        default: EmptyView()
        }
    }
}

/// Bottom half of a circle: a wide open smile.
private struct HalfCircle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 2))
        p.closeSubpath()
        return p
    }
}
