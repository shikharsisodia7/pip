import SwiftUI

enum BigButtonVariant {
    case primary, secondary, quiet
}

/// Chunky game-style pill button. Minimum height 64pt.
struct BigButton: View {
    private let title: String
    private let variant: BigButtonVariant
    private let systemImage: String?
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, variant: BigButtonVariant = .primary, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.variant = variant
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.pip(24, .bold))
            .padding(.horizontal, 36)
            .frame(minHeight: 64)
        }
        .buttonStyle(PipPillStyle(variant: variant))
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct PipPillStyle: ButtonStyle {
    let variant: BigButtonVariant

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundStyle(foreground)
            .background(fill(pressed: pressed))
            .contentShape(Capsule())
            .offset(y: pressed && variant != .quiet ? 4 : 0)
            .scaleEffect(pressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pressed)
    }

    private var foreground: Color {
        switch variant {
        case .primary: return Palette.text
        case .secondary: return Palette.text
        case .quiet: return Palette.textSoft
        }
    }

    @ViewBuilder
    private func fill(pressed: Bool) -> some View {
        switch variant {
        case .primary:
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Palette.accent, Palette.accent.opacity(0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5))
                .background(Capsule().fill(Palette.accentDeep).offset(y: pressed ? 2 : 6))
        case .secondary:
            Capsule()
                .fill(Palette.surfaceHigh)
                .overlay(Capsule().strokeBorder(Palette.stroke, lineWidth: 1.5))
                .background(Capsule().fill(Palette.bgBottom).offset(y: pressed ? 2 : 6))
        case .quiet:
            Color.clear
        }
    }
}

/// Round 56pt icon button, for secondary actions like replay or close.
struct RoundIconButton: View {
    private let systemImage: String
    private let tint: Color
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(systemImage: String, tint: Color = Palette.accent, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.text)
                .frame(width: 56, height: 56)
                .background(Circle().fill(tint))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5))
                .background(Circle().fill(Color.black.opacity(0.28)).offset(y: 4))
        }
        .buttonStyle(RoundPressStyle())
        .frame(minWidth: 60, minHeight: 60)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct RoundPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
