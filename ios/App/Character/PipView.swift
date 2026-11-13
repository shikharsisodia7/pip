import SwiftUI
import PipKit

enum PipState {
    case idle, listening, speaking, confused, thinking, celebrating
}

/// Pip, a small round creature who grows fancier as the child earns stars:
/// stage 1 Sprout (leaf), 2 Glow (aura), 3 Star (star badge), 4 Crown.
struct PipView: View {
    @Environment(Session.self) private var session
    private let state: PipState
    private let size: CGFloat

    @State private var bob = false

    init(state: PipState, size: CGFloat = 120) {
        self.state = state
        self.size = size
    }

    private var stage: Int { session.rewards.stage }
    private var color: Color { [Palette.mint, Palette.accent, Palette.purple, Palette.pink][max(0, min(stage - 1, 3))] }

    var body: some View {
        ZStack {
            if stage >= 2 {
                Circle()
                    .fill(color.opacity(0.45))
                    .frame(width: size * 1.15, height: size * 1.15)
                    .blur(radius: size * 0.14)
            }
            RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                .fill(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.9, height: size * 0.8)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                        .stroke(.white.opacity(0.35), lineWidth: size * 0.02)
                )
            HStack(spacing: size * 0.14) { eye; eye }
                .offset(y: -size * 0.06)
            mouth.offset(y: size * 0.16)
            topper.offset(y: -size * 0.47)
            if stage >= 3 {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: size * 0.2))
                    .foregroundStyle(Palette.sun, .white)
                    .offset(x: size * 0.36, y: size * 0.3)
            }
            badge.offset(x: size * 0.42, y: -size * 0.4)
        }
        .frame(width: size * 1.2, height: size * 1.2)
        .rotationEffect(.degrees(state == .confused ? -8 : 0))
        .offset(y: bob ? -size * 0.03 : size * 0.03)
        .animation(.easeInOut(duration: state == .celebrating ? 0.3 : 1.4).repeatForever(autoreverses: true), value: bob)
        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: stage)
        .animation(.spring, value: state)
        .onAppear { bob = true }
    }

    private var eye: some View {
        let big = state == .listening || state == .celebrating
        return ZStack {
            Ellipse().fill(.white)
                .frame(width: size * (big ? 0.2 : 0.17), height: size * (big ? 0.24 : 0.2))
            Circle().fill(Palette.ink)
                .frame(width: size * 0.09, height: size * 0.09)
                .offset(y: state == .thinking ? -size * 0.04 : 0)
        }
    }

    @ViewBuilder private var mouth: some View {
        switch state {
        case .speaking:
            Ellipse().fill(Palette.ink).frame(width: size * 0.14, height: size * (bob ? 0.1 : 0.05))
        case .confused:
            Capsule().fill(Palette.ink).frame(width: size * 0.12, height: size * 0.035).rotationEffect(.degrees(-12))
        default:
            Circle().trim(from: 0.08, to: 0.42)
                .stroke(Palette.ink, style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                .frame(width: size * 0.26, height: size * 0.26)
                .offset(y: -size * 0.1)
        }
    }

    @ViewBuilder private var topper: some View {
        if stage >= 4 {
            Image(systemName: "crown.fill").font(.system(size: size * 0.24)).foregroundStyle(Palette.sun)
        } else {
            Image(systemName: "leaf.fill").font(.system(size: size * 0.18)).foregroundStyle(Palette.mint)
                .rotationEffect(.degrees(-20))
        }
    }

    @ViewBuilder private var badge: some View {
        switch state {
        case .thinking: Image(systemName: "ellipsis.bubble.fill").font(.system(size: size * 0.2)).foregroundStyle(.white)
        case .confused: Image(systemName: "questionmark").font(.system(size: size * 0.2, weight: .heavy)).foregroundStyle(Palette.sun)
        case .celebrating: Image(systemName: "sparkles").font(.system(size: size * 0.22)).foregroundStyle(Palette.sun)
        case .listening: Image(systemName: "waveform").font(.system(size: size * 0.16, weight: .bold)).foregroundStyle(Palette.accent)
        default: EmptyView()
        }
    }
}
