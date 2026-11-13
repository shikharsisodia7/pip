import SwiftUI

/// Which side of the bubble the tail points from, toward the speaker.
enum BubbleTail {
    case left, right, bottom
}

/// A soft white speech bubble with a tail, matching the web SpeechBubble.
/// It pops in from the tail side when it appears.
struct SpeechBubble<Content: View>: View {
    private let tail: BubbleTail
    private let content: Content

    init(tail: BubbleTail = .left, @ViewBuilder content: () -> Content) {
        self.tail = tail
        self.content = content()
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private static var ink: Color { Color(.sRGB, red: 0x29 / 255, green: 0x25 / 255, blue: 0x24 / 255, opacity: 1) }
    private static var shadowTint: Color { Color(.sRGB, red: 0x4A / 255, green: 0x2A / 255, blue: 0x17 / 255, opacity: 1) }

    var body: some View {
        content
            .font(.system(.title3, design: .rounded))
            .foregroundStyle(Self.ink)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background {
                SpeechBubbleShape(tail: tail)
                    .fill(Color.white)
                    .shadow(color: Self.shadowTint.opacity(0.12), radius: 7, x: 0, y: 6)
                    .shadow(color: Self.shadowTint.opacity(0.08), radius: 1, x: 0, y: 1)
            }
            .padding(tailInsets)
            .scaleEffect(shown || reduceMotion ? 1 : 0.8, anchor: anchor)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .opacity(shown ? 1 : 0)
            .onAppear {
                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.2)) { shown = true }
                } else {
                    withAnimation(.interpolatingSpring(stiffness: 420, damping: 24)) { shown = true }
                }
            }
    }

    /// Reserves room for the tail so it never overlaps neighboring views.
    private var tailInsets: EdgeInsets {
        switch tail {
        case .left: EdgeInsets(top: 0, leading: SpeechBubbleShape.tailDepth, bottom: 0, trailing: 0)
        case .right: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: SpeechBubbleShape.tailDepth)
        case .bottom: EdgeInsets(top: 0, leading: 0, bottom: SpeechBubbleShape.tailDepth, trailing: 0)
        }
    }

    /// Where the pop-in grows from, so it starts at the speaker.
    private var anchor: UnitPoint {
        switch tail {
        case .left: UnitPoint(x: 0, y: 0.6)
        case .right: UnitPoint(x: 1, y: 0.6)
        case .bottom: UnitPoint(x: 0.5, y: 1)
        }
    }
}

/// The bubble body (24 pt corners) united with its tail into one outline, so
/// the shadow follows both as a single shape. The tail geometry is the web
/// tail SVG: 20 x 26 for side tails and 26 x 20 for the bottom tail, sitting
/// 15 pt outside the bubble edge.
private struct SpeechBubbleShape: Shape {
    let tail: BubbleTail

    static let tailDepth: CGFloat = 15
    private static let cornerRadius: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let bubble = Path(roundedRect: rect, cornerRadius: Self.cornerRadius, style: .continuous)
        return bubble.union(tailPath(in: rect))
    }

    private func tailPath(in rect: CGRect) -> Path {
        switch tail {
        case .left:
            // Tail box spans x from -15 to 5 and is centered at 60% height.
            let origin = CGPoint(x: rect.minX - 15, y: rect.minY + rect.height * 0.6 - 13)
            return Self.sideTail.applying(CGAffineTransform(translationX: origin.x, y: origin.y))
        case .right:
            let origin = CGPoint(x: rect.maxX + 15, y: rect.minY + rect.height * 0.6 - 13)
            return Self.sideTail.applying(
                CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: origin.x, ty: origin.y)
            )
        case .bottom:
            let origin = CGPoint(x: rect.midX - 13, y: rect.maxY - 5)
            return Self.bottomTail.applying(CGAffineTransform(translationX: origin.x, y: origin.y))
        }
    }

    /// M20 0 V26 C16 20 10 16 1 14 C-0.4 13.4 -0.4 12.6 1 12 C10 10 16 6 20 0 Z
    private static var sideTail: Path {
        Path { p in
            p.move(to: CGPoint(x: 20, y: 0))
            p.addLine(to: CGPoint(x: 20, y: 26))
            p.addCurve(to: CGPoint(x: 1, y: 14), control1: CGPoint(x: 16, y: 20), control2: CGPoint(x: 10, y: 16))
            p.addCurve(to: CGPoint(x: 1, y: 12), control1: CGPoint(x: -0.4, y: 13.4), control2: CGPoint(x: -0.4, y: 12.6))
            p.addCurve(to: CGPoint(x: 20, y: 0), control1: CGPoint(x: 10, y: 10), control2: CGPoint(x: 16, y: 6))
            p.closeSubpath()
        }
    }

    /// M0 0 H26 C20 4 16 10 14 19 C13.4 20.4 12.6 20.4 12 19 C10 10 6 4 0 0 Z
    private static var bottomTail: Path {
        Path { p in
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: 26, y: 0))
            p.addCurve(to: CGPoint(x: 14, y: 19), control1: CGPoint(x: 20, y: 4), control2: CGPoint(x: 16, y: 10))
            p.addCurve(to: CGPoint(x: 12, y: 19), control1: CGPoint(x: 13.4, y: 20.4), control2: CGPoint(x: 12.6, y: 20.4))
            p.addCurve(to: .zero, control1: CGPoint(x: 10, y: 10), control2: CGPoint(x: 6, y: 4))
            p.closeSubpath()
        }
    }
}
