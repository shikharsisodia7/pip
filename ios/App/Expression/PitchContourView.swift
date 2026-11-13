import SwiftUI
import PipKit

/// Live pitch contour: the reader's voice as a thick glowing line that rises and
/// falls with their pitch, drawn over a dull flat line showing how Pip read it.
/// Built to be readable from the back of a room.
struct PitchContourView: View {
    var frames: [ProsodyFrame]
    var active: Bool = false
    var windowSeconds: Double = 5
    var showPipLine: Bool = true

    private let rangeSemitones: Double = 9
    private let padX: CGFloat = 24

    var body: some View {
        TimelineView(.animation(paused: !active)) { timeline in
            Canvas { ctx, size in
                draw(in: &ctx, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.992, blue: 0.973),
                                              Color(red: 1, green: 0.949, blue: 0.788)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(alignment: .center) {
            if !frames.contains(where: { $0.semitones != nil }) {
                Text(active ? "Say it out loud!" : "Your voice will draw here")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.56, green: 0.5, blue: 0.42))
                    .offset(y: 34)
            }
        }
        .accessibilityLabel("Your voice, drawn as a line that goes up and down")
    }

    private func y(for st: Double, height: CGFloat) -> CGFloat {
        let c = max(-rangeSemitones, min(rangeSemitones, st))
        return height / 2 - CGFloat(c / rangeSemitones) * (height / 2 - 26)
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let h = size.height
        let w = size.width

        // Guide lines.
        for st in [-6.0, -3.0, 3.0, 6.0] {
            var p = Path()
            p.move(to: CGPoint(x: padX, y: y(for: st, height: h)))
            p.addLine(to: CGPoint(x: w - padX, y: y(for: st, height: h)))
            ctx.stroke(p, with: .color(Color(red: 0.937, green: 0.89, blue: 0.81)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 10]))
        }

        // Pip's flat read.
        if showPipLine {
            var flat = Path()
            flat.move(to: CGPoint(x: padX, y: h / 2))
            flat.addLine(to: CGPoint(x: w - padX, y: h / 2))
            ctx.stroke(flat, with: .color(Color(red: 0.725, green: 0.67, blue: 0.6).opacity(0.6)),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round))
            ctx.draw(Text("how Pip said it")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.56, green: 0.5, blue: 0.42)),
                     at: CGPoint(x: w - padX - 70, y: h / 2 - 16))
        }

        guard let first = frames.first else { return }
        let span = max(windowSeconds, (frames.last?.t ?? 0) - first.t)
        func x(_ t: Double) -> CGFloat { padX + CGFloat((t - first.t) / span) * (w - padX * 2) }

        // Segments split at pauses longer than 250 ms.
        var segments: [[CGPoint]] = []
        var current: [CGPoint] = []
        var lastT = -Double.infinity
        for f in frames {
            guard let st = f.semitones else { continue }
            if f.t - lastT > 0.25, !current.isEmpty { segments.append(current); current = [] }
            current.append(CGPoint(x: x(f.t), y: y(for: st, height: h)))
            lastT = f.t
        }
        if !current.isEmpty { segments.append(current) }

        let gradient = Gradient(colors: [Color(red: 1, green: 0.71, blue: 0.28),
                                         Color(red: 1, green: 0.48, blue: 0.35),
                                         Color(red: 0.227, green: 0.357, blue: 0.863)])
        let shading = GraphicsContext.Shading.linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: w, y: 0))

        for seg in segments {
            let path = Self.smoothPath(seg)
            var glow = ctx
            glow.addFilter(.blur(radius: 8))
            glow.stroke(path, with: shading, style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
        }

        // Pulsing head while recording.
        if active, let head = segments.last?.last {
            let r = 11 + 3 * sin(time * 7)
            let dot = Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2))
            ctx.fill(dot, with: .color(Color(red: 1, green: 0.48, blue: 0.35)))
            ctx.stroke(dot, with: .color(.white), lineWidth: 3)
        }
    }

    /// Catmull-Rom spline through the points.
    static func smoothPath(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        if pts.count == 1 { p.addLine(to: CGPoint(x: first.x + 0.1, y: first.y)); return p }
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        return p
    }
}
