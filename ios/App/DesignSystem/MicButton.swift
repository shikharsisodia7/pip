import SwiftUI

enum MicState {
    case idle, listening, disabled
}

/// idle: tap to start listening. listening: pulsing, tap to stop. disabled: Pip is talking.
struct MicButton: View {
    private let state: MicState
    private let label: String?
    private let size: CGFloat
    private let action: () -> Void

    @State private var pulse = false

    init(state: MicState, label: String? = nil, size: CGFloat = 110, action: @escaping () -> Void) {
        self.state = state
        self.label = label
        self.size = size
        self.action = action
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                if state == .listening {
                    ForEach(0..<2, id: \.self) { i in
                        Circle()
                            .fill(Palette.sun)
                            .frame(width: size, height: size)
                            .scaleEffect(pulse ? 1.7 : 1)
                            .opacity(pulse ? 0 : 0.55)
                            .animation(
                                .easeOut(duration: 1.4)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(i) * 0.6),
                                value: pulse
                            )
                            .allowsHitTesting(false)
                    }
                }
                Button(action: action) {
                    ZStack {
                        Circle().fill(fillColor)
                        Circle().strokeBorder(Color.white.opacity(state == .disabled ? 0.08 : 0.25), lineWidth: 2)
                        icon
                    }
                    .frame(width: size, height: size)
                    .background(
                        Circle()
                            .fill(state == .idle ? Palette.accentDeep : Color.clear)
                            .offset(y: 7)
                    )
                }
                .buttonStyle(MicPressStyle())
                .disabled(state == .disabled)
                .accessibilityLabel(state == .listening ? "Stop listening" : "Start listening")
            }
            .frame(width: size, height: size)

            Text(label ?? defaultLabel)
                .font(.pip(20, .semibold))
                .foregroundStyle(state == .disabled ? Palette.textSoft : Palette.text)
                .multilineTextAlignment(.center)
        }
        .onAppear { pulse = state == .listening }
        .onChange(of: state) { _, newValue in pulse = newValue == .listening }
    }

    private var defaultLabel: String {
        switch state {
        case .idle: return "Tap to read"
        case .listening: return "Listening... tap when you finish"
        case .disabled: return "Pip is talking"
        }
    }

    private var fillColor: Color {
        switch state {
        case .idle: return Palette.accent
        case .listening: return Palette.accentDeep
        case .disabled: return Palette.surfaceHigh
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .listening:
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .fill(Color.white)
                .frame(width: size * 0.3, height: size * 0.3)
        case .idle:
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
        case .disabled:
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(Palette.textSoft)
        }
    }
}

private struct MicPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
