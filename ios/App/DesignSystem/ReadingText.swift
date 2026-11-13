import SwiftUI
import PipKit

/// Story text that lights up word by word while the child reads. Each word is a
/// soft pill colored by its WordMark: green when read, warm yellow after a long
/// pause, coral when skipped or misread, a glow on the next word to read.
struct ReadingText: View {
    private let text: String
    private let marks: [WordMark]
    private let fontSize: CGFloat

    init(text: String, marks: [WordMark], fontSize: CGFloat = 34) {
        self.text = text
        self.marks = marks
        self.fontSize = fontSize
    }

    var body: some View {
        let tokens = tokenizeDisplay(text)
        FlowLayout(spacing: fontSize * 0.1, lineSpacing: fontSize * 0.28) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { i, token in
                WordPill(word: token.display, mark: i < marks.count ? marks[i] : .pending, fontSize: fontSize)
            }
        }
    }
}

/// Three dot key shown under the story text.
struct ReadingLegend: View {
    var body: some View {
        HStack(spacing: 18) {
            item(.correct, "got it")
            item(.hesitant, "took a moment")
            item(.missed, "tricky")
        }
        .font(.pip(15, .semibold))
    }

    private func item(_ mark: WordMark, _ label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(mark.ink).frame(width: 10, height: 10)
            Text(label).foregroundStyle(Palette.ink.opacity(0.7))
        }
    }
}

extension WordMark {
    /// Text color on the paper card.
    var ink: Color {
        switch self {
        case .pending: return Palette.ink.opacity(0.45)
        case .current: return Palette.ink
        case .correct, .fixed: return Color(hex: 0x1F8A5B)
        case .hesitant: return Color(hex: 0xA26A00)
        case .missed: return Color(hex: 0xD2502A)
        }
    }

    /// Pill fill behind the word.
    var fill: Color {
        switch self {
        case .pending: return .clear
        case .current: return Palette.accent.opacity(0.18)
        case .correct, .fixed: return Color(hex: 0xD3F5E4)
        case .hesitant: return Color(hex: 0xFFEDB5)
        case .missed: return Color(hex: 0xFFE0D4)
        }
    }
}

private struct WordPill: View {
    let word: String
    let mark: WordMark
    let fontSize: CGFloat

    @State private var glow = false

    var body: some View {
        Text(word)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(mark.ink)
            .padding(.horizontal, fontSize * 0.16)
            .padding(.vertical, fontSize * 0.04)
            .background(RoundedRectangle(cornerRadius: fontSize * 0.3, style: .continuous).fill(mark.fill))
            .overlay(alignment: .bottom) {
                if mark == .current {
                    Capsule().fill(Palette.accent)
                        .frame(height: 4)
                        .padding(.horizontal, fontSize * 0.12)
                        .opacity(glow ? 1 : 0.3)
                        .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever()) { glow = true } }
                        .onDisappear { glow = false }
                }
            }
            .overlay(alignment: .topTrailing) {
                if mark == .fixed {
                    Image(systemName: "sparkle")
                        .font(.system(size: fontSize * 0.4, weight: .bold))
                        .foregroundStyle(Palette.sun)
                        .offset(x: fontSize * 0.15, y: -fontSize * 0.2)
                }
            }
            .scaleEffect(mark == .current ? 1.06 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: mark)
    }
}

/// Left to right wrapping layout for word pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
