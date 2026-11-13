import SwiftUI

enum MeterTone {
    case accent, sun, muted
}

/// Horizontal rounded bar. value is clamped to 0...1.
struct Meter: View {
    private let value: Double
    private let label: String?
    private let valueLabel: String?
    private let tone: MeterTone
    private let height: CGFloat

    @State private var shown: Double = 0

    init(value: Double, label: String? = nil, valueLabel: String? = nil, tone: MeterTone = .accent, height: CGFloat = 18) {
        self.value = value
        self.label = label
        self.valueLabel = valueLabel
        self.tone = tone
        self.height = height
    }

    private var clamped: Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }

    private var toneColor: Color {
        switch tone {
        case .accent: return Palette.accent
        case .sun: return Palette.sun
        case .muted: return Palette.textSoft.opacity(0.5)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if label != nil || valueLabel != nil {
                HStack {
                    if let label {
                        Text(label)
                            .font(.pip(17, .medium))
                            .foregroundStyle(Palette.textSoft)
                    }
                    Spacer(minLength: 8)
                    if let valueLabel {
                        Text(valueLabel)
                            .font(.pip(17, .bold))
                            .foregroundStyle(Palette.text)
                    }
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(toneColor)
                        .overlay(Capsule().fill(Color.white.opacity(0.25)).frame(height: height * 0.3).offset(y: -height * 0.18).padding(.horizontal, height * 0.3))
                        .frame(width: max(0, geo.size.width * shown))
                }
            }
            .frame(height: height)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { shown = clamped }
        }
        .onChange(of: clamped) { _, newValue in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { shown = newValue }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Meter")
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}
