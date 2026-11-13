import SwiftUI

// Pip the owl, drawn natively from the same vector art as the web component
// (components/pip/Owl.tsx). All geometry lives in a 240 x 240 design space
// and is scaled to the requested size. Each body part is drawn as its own
// layer so it can move independently, and every animation is a pure function
// of time, which keeps the motion identical to the web keyframes.

enum OwlState {
    case idle, listening, speaking, confused, thinking, celebrating
}

struct OwlView: View {
    private let state: OwlState
    private let size: CGFloat

    init(state: OwlState, size: CGFloat) {
        self.state = state
        self.size = size
        _current = State(initialValue: state)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The state being drawn. It trails `state` by one update so the pose at
    /// the moment of change can be captured before the new state takes over.
    @State private var current: OwlState
    @State private var enteredAt = Date()
    @State private var fromPose: OwlPose?
    @State private var blinkAt: Date?
    /// Keeps the timeline running briefly under Reduce Motion so fades and
    /// blinks can finish; otherwise the timeline is paused while still.
    @State private var stillActivity = 0
    @State private var stillAnimating = false

    private var timelinePaused: Bool { reduceMotion && !stillAnimating }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: timelinePaused)) { context in
            // A paused timeline may hold a stale date, so draw the settled pose.
            let now = timelinePaused ? Date.distantFuture : context.date
            OwlCanvas(pose: pose(at: now), blink: blink(at: now), size: size)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel("Pip the owl")
        .accessibilityAddTraits(.isImage)
        .onChange(of: state) { _, newState in
            let now = Date()
            fromPose = pose(at: now)
            current = newState
            enteredAt = now
            stillActivity += 1
        }
        .task { await runBlinkLoop() }
        .task(id: stillActivity) {
            guard reduceMotion, stillActivity > 0 else { return }
            stillAnimating = true
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            stillAnimating = false
        }
    }

    private func pose(at now: Date) -> OwlPose {
        let elapsed = max(0, now.timeIntervalSince(enteredAt))
        let target = OwlPose.target(for: current, time: reduceMotion ? 0 : elapsed)
        guard let fromPose, elapsed < 2 else { return target }
        let blend = OwlBlend(elapsed: elapsed, target: current, reduced: reduceMotion)
        return OwlPose.blend(from: fromPose, to: target, with: blend)
    }

    private func blink(at now: Date) -> OwlBlink {
        guard let blinkAt else { return .open }
        return OwlBlink.at(now.timeIntervalSince(blinkAt))
    }

    /// Blinks on a random 2.5 to 6 second interval, with an occasional quick
    /// double blink, matching the web timing.
    private func runBlinkLoop() async {
        var delay = Double.random(in: 1.2...3.7)
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(delay))
                blinkAt = Date()
                stillActivity += 1
                try await Task.sleep(for: .milliseconds(130))
            } catch {
                return
            }
            delay = Double.random(in: 0...1) < 0.18 ? 0.18 : Double.random(in: 2.5...6)
        }
    }
}

// MARK: - Palette

enum OwlPalette {
    static let outline = rgb(0x4A2A17)
    static let body = rgb(0xC47A3F)
    static let bodyShade = rgb(0xA9612E)
    static let wing = rgb(0x9A562A)
    static let wingLight = rgb(0xB46B35)
    static let tuft = rgb(0x8F4F26)
    static let face = rgb(0xF9E0B9)
    static let belly = rgb(0xFDEED7)
    static let bellyMark = rgb(0xE8C799)
    static let eyeWhite = Color.white
    static let iris = rgb(0x8A4A22)
    static let pupil = rgb(0x2A1910)
    static let lid = rgb(0xE9BE86)
    static let beak = rgb(0xF6A12E)
    static let beakShade = rgb(0xDB7B17)
    static let mouth = rgb(0x7A2E1C)
    static let tongue = rgb(0xF07F6C)
    static let feet = rgb(0xF6A12E)
    static let cheek = rgb(0xF28B74)
    static let brow = rgb(0x6B3A1E)
    static let accent = rgb(0xE5792B)
    static let sparkle = rgb(0xFFC23D)
    static let shadow = rgb(0x4A2A17)

    static func rgb(_ hex: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Pose

/// Every animatable value of the owl. Units follow the web component:
/// offsets in design points, rotations in degrees, scales as factors.
struct OwlPose {
    var bodyY = 0.0
    var bodyScaleX = 1.0
    var bodyScaleY = 1.0
    var shadowScaleX = 1.0
    var shadowOpacity = 0.16
    var headRotate = 0.0
    var headY = 0.0
    var headScale = 1.0
    var tuftRotate = 0.0
    var tuftScaleY = 1.0
    var tuftY = 0.0
    var wingRotate = 0.0
    var browLeftY = 0.0
    var browLeftRotate = 0.0
    var browRightY = 0.0
    var browRightRotate = 0.0
    var pupilX = 0.0
    var pupilY = 1.0
    var pupilScale = 1.0
    var openEye = 1.0
    var happyEye = 0.0
    var lowerBeakY = 0.0
    var mouthScaleY = 0.0
    var cheekOpacity = 0.42
    var questionOpacity = 0.0
    var questionScale = 0.3
    var questionRotate = 0.0
    var questionY = 8.0
    var dotOpacity: [Double] = [0, 0, 0]
    var dotScale: [Double] = [0.4, 0.4, 0.4]
    var sparkleOpacity: [Double] = [0, 0, 0, 0]
    var sparkleScale: [Double] = [0, 0, 0, 0]
    var sparkleRotate: [Double] = [0, 0, 0, 0]

    private static let hop = 0.72
    private static let hopTimes = [0, 0.42, 0.78, 1]
    private static let speakTimes = [0, 0.2, 0.45, 0.65, 1]

    /// The pose for a state at `time` seconds after entering it. Each looping
    /// keyframe list starts on its resting value, so time zero doubles as the
    /// still pose used under Reduce Motion.
    static func target(for state: OwlState, time t: Double) -> OwlPose {
        var p = OwlPose()
        switch state {
        case .idle:
            p.bodyScaleY = loop([1, 1.022, 1], 3.4, t)
            p.bodyScaleX = loop([1, 0.992, 1], 3.4, t)
            p.headRotate = loop([0, 2.5, 0, -2.5, 0], 7, t)
            p.tuftRotate = loop([0, -3, 0], 3.4, t)
            p.wingRotate = loop([0, 4, 0], 3.4, t)
            p.pupilX = loop([0, 0, 3, 3, 0], 8, t, times: [0, 0.45, 0.5, 0.85, 0.9])

        case .listening:
            p.shadowScaleX = 1.03
            p.headRotate = 3
            p.headY = 5
            p.headScale = 1.045
            p.tuftRotate = 12
            p.tuftScaleY = 1.16
            p.tuftY = -3
            p.wingRotate = -4
            p.browLeftY = -5
            p.browRightY = -5
            p.pupilY = 2
            p.pupilScale = 1.12

        case .speaking:
            p.bodyY = loop([0, -5, 0], 0.5, t)
            p.bodyScaleY = loop([1, 1.02, 1], 0.5, t)
            p.shadowScaleX = loop([1, 0.94, 1], 0.5, t)
            p.headRotate = loop([0, -2, 0, 2, 0], 1.8, t)
            p.tuftRotate = loop([0, 4, 0], 0.5, t)
            p.wingRotate = loop([4, 12, 4], 1, t)
            p.browLeftY = loop([-1, -3, -1], 0.5, t)
            p.browRightY = p.browLeftY
            p.lowerBeakY = loop([11, 0.5, 8, 1.5, 11], 0.62, t, times: speakTimes)
            p.mouthScaleY = loop([1, 0.08, 0.85, 0.15, 1], 0.62, t, times: speakTimes)
            p.cheekOpacity = 0.5

        case .confused:
            p.headRotate = -12
            p.headY = 1
            p.tuftRotate = 4
            p.tuftScaleY = 0.95
            p.tuftY = 1
            p.wingRotate = 24
            p.browLeftY = -8
            p.browLeftRotate = -10
            p.browRightY = 2
            p.browRightRotate = -12
            p.pupilX = -4
            p.pupilY = -1
            p.pupilScale = 0.92
            p.lowerBeakY = 5
            p.mouthScaleY = 0.4
            p.cheekOpacity = 0.3
            p.questionOpacity = 1
            p.questionScale = 1
            p.questionY = 0
            p.questionRotate = loop([0, 10, 0, -6, 0], 2.4, t, delay: 0.3)

        case .thinking:
            p.headRotate = -6
            p.headY = -1
            p.tuftRotate = 4
            p.tuftScaleY = 1.04
            p.wingRotate = 6
            p.browLeftY = -6
            p.browLeftRotate = -5
            p.browRightY = -6
            p.browRightRotate = 5
            p.pupilX = 6
            p.pupilY = -8
            p.pupilScale = 0.95
            p.cheekOpacity = 0.36
            for i in 0..<3 {
                p.dotOpacity[i] = loop([1, 0.35, 1], 1.2, t, delay: Double(i) * 0.2)
                p.dotScale[i] = loop([1, 0.8, 1], 1.2, t, delay: Double(i) * 0.2)
            }

        case .celebrating:
            p.bodyY = loop([0, -20, 0, 0], hop, t, times: hopTimes, ease: .easeOut)
            p.bodyScaleY = loop([1, 1.04, 0.92, 1], hop, t, times: hopTimes, ease: .easeOut)
            p.bodyScaleX = loop([1, 0.97, 1.07, 1], hop, t, times: hopTimes, ease: .easeOut)
            p.shadowScaleX = loop([1, 0.68, 1, 1], hop, t, times: hopTimes, ease: .easeOut)
            p.shadowOpacity = loop([0.16, 0.08, 0.16, 0.16], hop, t, times: hopTimes, ease: .easeOut)
            p.headRotate = loop([-4, 4, -4], hop * 2, t)
            p.headScale = 1.02
            p.tuftRotate = loop([8, -4, 8], hop, t)
            p.tuftScaleY = 1.12
            p.tuftY = -2
            p.wingRotate = loop([122, 146, 122], hop / 2, t)
            p.browLeftY = -8
            p.browRightY = -8
            p.pupilY = 0
            p.openEye = 0
            p.happyEye = 1
            p.lowerBeakY = 12
            p.mouthScaleY = 1.1
            p.cheekOpacity = 0.8
            for i in 0..<4 {
                let delay = Double(i) * 0.17
                p.sparkleOpacity[i] = loop([1, 0.55, 1], 0.9, t, delay: delay)
                p.sparkleScale[i] = loop([1, 0.45, 1], 0.9, t, delay: delay)
                p.sparkleRotate[i] = loop([0, 45, 90], 0.9, t, delay: delay)
            }
        }
        return p
    }

    /// Moves from a captured pose toward a live target, using a different
    /// curve per group of properties as the web springs do.
    static func blend(from a: OwlPose, to b: OwlPose, with k: OwlBlend) -> OwlPose {
        func mix(_ x: Double, _ y: Double, _ f: Double) -> Double { x + (y - x) * f }
        func mix(_ x: [Double], _ y: [Double], _ f: Double) -> [Double] {
            zip(x, y).map { mix($0, $1, f) }
        }
        var p = OwlPose()
        p.bodyY = mix(a.bodyY, b.bodyY, k.general)
        p.bodyScaleX = mix(a.bodyScaleX, b.bodyScaleX, k.general)
        p.bodyScaleY = mix(a.bodyScaleY, b.bodyScaleY, k.general)
        p.shadowScaleX = mix(a.shadowScaleX, b.shadowScaleX, k.general)
        p.shadowOpacity = mix(a.shadowOpacity, b.shadowOpacity, k.general)
        p.headRotate = mix(a.headRotate, b.headRotate, k.head)
        p.headY = mix(a.headY, b.headY, k.soft)
        p.headScale = mix(a.headScale, b.headScale, k.soft)
        p.tuftRotate = mix(a.tuftRotate, b.tuftRotate, k.soft)
        p.tuftScaleY = mix(a.tuftScaleY, b.tuftScaleY, k.soft)
        p.tuftY = mix(a.tuftY, b.tuftY, k.soft)
        p.wingRotate = mix(a.wingRotate, b.wingRotate, k.soft)
        p.browLeftY = mix(a.browLeftY, b.browLeftY, k.general)
        p.browLeftRotate = mix(a.browLeftRotate, b.browLeftRotate, k.general)
        p.browRightY = mix(a.browRightY, b.browRightY, k.general)
        p.browRightRotate = mix(a.browRightRotate, b.browRightRotate, k.general)
        p.pupilX = mix(a.pupilX, b.pupilX, k.general)
        p.pupilY = mix(a.pupilY, b.pupilY, k.general)
        p.pupilScale = mix(a.pupilScale, b.pupilScale, k.general)
        p.openEye = mix(a.openEye, b.openEye, k.fade)
        p.happyEye = mix(a.happyEye, b.happyEye, k.fade)
        p.lowerBeakY = mix(a.lowerBeakY, b.lowerBeakY, k.general)
        p.mouthScaleY = mix(a.mouthScaleY, b.mouthScaleY, k.general)
        p.cheekOpacity = mix(a.cheekOpacity, b.cheekOpacity, k.fade)
        p.questionOpacity = mix(a.questionOpacity, b.questionOpacity, k.fade)
        p.questionScale = mix(a.questionScale, b.questionScale, k.pop)
        p.questionRotate = mix(a.questionRotate, b.questionRotate, k.general)
        p.questionY = mix(a.questionY, b.questionY, k.general)
        p.dotOpacity = mix(a.dotOpacity, b.dotOpacity, k.fade)
        p.dotScale = mix(a.dotScale, b.dotScale, k.general)
        p.sparkleOpacity = mix(a.sparkleOpacity, b.sparkleOpacity, k.fade)
        p.sparkleScale = mix(a.sparkleScale, b.sparkleScale, k.general)
        p.sparkleRotate = mix(a.sparkleRotate, b.sparkleRotate, k.general)
        return p
    }

    /// Samples a repeating keyframe list. Values are evenly spaced unless
    /// `times` is given; the easing applies to each segment, and the delay
    /// only shifts the first cycle, as in framer-motion.
    static func loop(
        _ values: [Double],
        _ duration: Double,
        _ t: Double,
        times: [Double]? = nil,
        delay: Double = 0,
        ease: OwlEase = .easeInOut
    ) -> Double {
        guard values.count > 1 else { return values.first ?? 0 }
        let local = max(0, t - delay)
        let progress = local.truncatingRemainder(dividingBy: duration) / duration
        let stops = times ?? values.indices.map { Double($0) / Double(values.count - 1) }
        for i in 1..<stops.count where progress < stops[i] {
            let span = stops[i] - stops[i - 1]
            let s = span > 0 ? (progress - stops[i - 1]) / span : 1
            return values[i - 1] + (values[i] - values[i - 1]) * ease.apply(s)
        }
        return values[values.count - 1]
    }
}

/// Blend factors from 0 to 1 for each property group during a state change.
struct OwlBlend {
    var general: Double
    var soft: Double
    var head: Double
    var fade: Double
    var pop: Double

    init(elapsed t: Double, target: OwlState, reduced: Bool) {
        if reduced {
            let k = min(1, max(0, t / 0.2))
            general = k; soft = k; head = k; fade = k; pop = k
            return
        }
        general = Self.spring(t, stiffness: 260, damping: 18)
        soft = Self.spring(t, stiffness: 160, damping: 14)
        switch target {
        case .confused: head = Self.spring(t, stiffness: 220, damping: 11)
        case .listening, .thinking: head = soft
        default: head = general
        }
        fade = min(1, t / 0.15)
        pop = Self.spring(t, stiffness: 380, damping: 12)
    }

    /// Step response of a damped spring with unit mass.
    static func spring(_ t: Double, stiffness: Double, damping: Double) -> Double {
        guard t > 0 else { return 0 }
        let w0 = stiffness.squareRoot()
        let zeta = damping / (2 * w0)
        if zeta < 1 {
            let wd = w0 * (1 - zeta * zeta).squareRoot()
            let decay = exp(-zeta * w0 * t)
            return 1 - decay * (cos(wd * t) + zeta * w0 / wd * sin(wd * t))
        }
        return 1 - exp(-w0 * t) * (1 + w0 * t)
    }
}

/// Cubic bezier easing curves matching the CSS keywords framer-motion uses.
struct OwlEase {
    let x1: Double, y1: Double, x2: Double, y2: Double

    static let easeInOut = OwlEase(x1: 0.42, y1: 0, x2: 0.58, y2: 1)
    static let easeOut = OwlEase(x1: 0, y1: 0, x2: 0.58, y2: 1)

    func apply(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        // Bisection on x is robust and plenty fast for a handful of values.
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<24 {
            t = (lo + hi) / 2
            if bezier(t, x1, x2) < x { lo = t } else { hi = t }
        }
        return bezier(t, y1, y2)
    }
}

/// Eyelid closure and the closed-eye line for one blink.
struct OwlBlink {
    var lid: Double
    var line: Double

    static let open = OwlBlink(lid: 0, line: 0)

    /// Lids close in 70 ms, hold until 130 ms, then open over 110 ms.
    static func at(_ t: Double) -> OwlBlink {
        guard t >= 0, t < 0.3 else { return .open }
        let easeOut = OwlEase.easeOut
        let lid: Double
        if t < 0.07 {
            lid = easeOut.apply(t / 0.07)
        } else if t < 0.13 {
            lid = 1
        } else {
            lid = 1 - easeOut.apply(min(1, (t - 0.13) / 0.11))
        }
        let line = t < 0.13
            ? min(1, max(0, (t - 0.05) / 0.05))
            : 1 - min(1, (t - 0.13) / 0.05)
        return OwlBlink(lid: lid, line: line)
    }
}

// MARK: - Drawing

/// Draws one frame of the owl for a given pose. The art may extend past the
/// nominal frame (raised wings, hops, the question mark), so the canvas is
/// larger than the layout size and centered on it.
struct OwlCanvas: View {
    let pose: OwlPose
    let blink: OwlBlink
    let size: CGFloat

    private static let overflow: CGFloat = 0.2

    var body: some View {
        let margin = size * Self.overflow
        Canvas { context, _ in
            var gc = context
            gc.translateBy(x: margin, y: margin)
            gc.scaleBy(x: size / 240, y: size / 240)
            OwlRenderer(pose: pose, blink: blink).draw(in: gc)
        }
        .frame(width: size + margin * 2, height: size + margin * 2)
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

private struct OwlRenderer {
    let pose: OwlPose
    let blink: OwlBlink

    private typealias C = OwlPalette
    private static let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 240, ty: 0)
    private static let eyeRadius: CGFloat = 24
    private static let leftEye = CGPoint(x: 93, y: 100)
    private static let rightEye = CGPoint(x: 147, y: 100)
    private static let groundY: CGFloat = 226

    func draw(in gc: GraphicsContext) {
        drawShadow(gc)

        let body = Self.transformed(
            gc, pivot: CGPoint(x: 120, y: Self.groundY),
            y: pose.bodyY, scaleX: pose.bodyScaleX, scaleY: pose.bodyScaleY
        )
        drawBody(body)
        drawFeet(body)
        drawWing(Self.transformed(body, pivot: CGPoint(x: 76, y: 144), rotate: pose.wingRotate))
        drawWing(Self.transformed(Self.mirrored(body), pivot: CGPoint(x: 76, y: 144), rotate: pose.wingRotate))

        let head = Self.transformed(
            body, pivot: CGPoint(x: 120, y: 152),
            y: pose.headY, scaleX: pose.headScale, scaleY: pose.headScale, rotate: pose.headRotate
        )
        drawHead(head)

        drawQuestion(gc)
        drawThoughtDots(gc)
        drawSparkles(gc)
    }

    // MARK: Parts

    private func drawShadow(_ gc: GraphicsContext) {
        var g = Self.transformed(gc, pivot: CGPoint(x: 120, y: Self.groundY + 2), scaleX: pose.shadowScaleX)
        g.opacity = pose.shadowOpacity
        g.fill(Self.ellipse(120, Self.groundY + 2, 50, 6), with: .color(C.shadow))
    }

    private func drawBody(_ gc: GraphicsContext) {
        let body = Self.ellipse(120, 172, 58, 52)
        gc.fill(body, with: .color(C.body))
        var shade = gc
        shade.clip(to: body)
        shade.opacity = 0.55
        shade.fill(Self.ellipse(136, 210, 70, 34), with: .color(C.bodyShade))
        gc.stroke(body, with: .color(C.outline), style: Self.outline(3))

        gc.fill(Self.ellipse(120, 180, 37, 38), with: .color(C.belly))
        gc.stroke(OwlPaths.bellyMarks, with: .color(C.bellyMark), style: Self.outline(2.6))
    }

    private func drawFeet(_ gc: GraphicsContext) {
        let toes: [(CGFloat, CGFloat)] = [(95, 222), (104, 224), (113, 222), (127, 222), (136, 224), (145, 222)]
        for (x, y) in toes {
            let toe = Self.ellipse(x, y, 5.5, 6.5)
            gc.fill(toe, with: .color(C.feet))
            gc.stroke(toe, with: .color(C.outline), style: Self.outline(2.5))
        }
    }

    private func drawWing(_ gc: GraphicsContext) {
        gc.fill(OwlPaths.wing, with: .color(C.wing))
        gc.stroke(OwlPaths.wing, with: .color(C.outline), style: Self.outline(3))
        gc.stroke(OwlPaths.wingFeather1, with: .color(C.wingLight), style: Self.outline(3))
        var faint = gc
        faint.opacity = 0.8
        faint.stroke(OwlPaths.wingFeather2, with: .color(C.wingLight), style: Self.outline(2.5))
    }

    private func drawTuft(_ gc: GraphicsContext) {
        let g = Self.transformed(
            gc, pivot: CGPoint(x: 80, y: 58),
            y: pose.tuftY, scaleY: pose.tuftScaleY, rotate: pose.tuftRotate
        )
        g.fill(OwlPaths.tuft, with: .color(C.tuft))
        g.stroke(OwlPaths.tuft, with: .color(C.outline), style: Self.outline(3))
        var streak = g
        streak.opacity = 0.75
        streak.stroke(OwlPaths.tuftStreak, with: .color(C.wingLight), style: Self.outline(2.6))
    }

    private func drawHead(_ gc: GraphicsContext) {
        drawTuft(gc)
        drawTuft(Self.mirrored(gc))

        let head = OwlPaths.head
        gc.fill(head, with: .color(C.body))
        var sheen = gc
        sheen.clip(to: head)
        sheen.opacity = 0.12
        sheen.fill(Self.ellipse(96, 52, 44, 18), with: .color(.white))
        gc.stroke(head, with: .color(C.outline), style: Self.outline(3))

        // Facial disc
        var disc = Path()
        disc.addPath(Self.ellipse(Self.leftEye.x, Self.leftEye.y, 35, 35))
        disc.addPath(Self.ellipse(Self.rightEye.x, Self.rightEye.y, 35, 35))
        disc.addPath(Self.ellipse(120, 122, 30, 22))
        gc.fill(disc, with: .color(C.face))

        var cheeks = gc
        cheeks.opacity = pose.cheekOpacity
        cheeks.fill(Self.ellipse(70, 128, 10, 6), with: .color(C.cheek))
        cheeks.fill(Self.ellipse(170, 128, 10, 6), with: .color(C.cheek))

        drawEye(gc, center: Self.leftEye, isLeft: true)
        drawEye(gc, center: Self.rightEye, isLeft: false)
        drawBrows(gc)
        drawBeak(gc)
    }

    private func drawEye(_ gc: GraphicsContext, center c: CGPoint, isLeft: Bool) {
        let r = Self.eyeRadius
        if pose.openEye > 0.001 {
            var group = gc
            group.opacity = pose.openEye
            group.drawLayer { layer in
                let ball = Self.ellipse(c.x, c.y, r, r)
                layer.fill(ball, with: .color(C.eyeWhite))

                var inside = layer
                inside.clip(to: ball)

                let look = Self.transformed(
                    inside, pivot: c, x: pose.pupilX, y: pose.pupilY,
                    scaleX: pose.pupilScale, scaleY: pose.pupilScale
                )
                let irisX = c.x + (isLeft ? 2 : -2)
                look.fill(Self.ellipse(irisX, c.y + 2, 15, 15), with: .color(C.iris))
                look.fill(Self.ellipse(irisX, c.y + 2, 11, 11), with: .color(C.pupil))
                look.fill(Self.ellipse(c.x + (isLeft ? 7 : 3), c.y - 4, 5.2, 5.2), with: .color(C.eyeWhite))
                var glint = look
                glint.opacity = 0.9
                glint.fill(Self.ellipse(c.x + (isLeft ? -3 : -7), c.y + 7, 2.3, 2.3), with: .color(C.eyeWhite))

                if blink.lid > 0.001 {
                    let lid = Self.transformed(inside, pivot: CGPoint(x: c.x, y: c.y - r - 2), scaleY: blink.lid)
                    lid.fill(Self.ellipse(c.x, c.y, r + 2, r + 2), with: .color(C.lid))
                }
                if blink.line > 0.001 {
                    var line = inside
                    line.opacity = blink.line
                    var lash = Path()
                    lash.move(to: CGPoint(x: c.x - 20, y: c.y + 3))
                    lash.addQuadCurve(to: CGPoint(x: c.x + 20, y: c.y + 3), control: CGPoint(x: c.x, y: c.y + 13))
                    line.stroke(lash, with: .color(C.outline), style: Self.outline(3.5))
                }

                layer.stroke(ball, with: .color(C.outline), style: Self.outline(2.5))
            }
        }

        if pose.happyEye > 0.001 {
            var happy = gc
            happy.opacity = pose.happyEye
            var arc = Path()
            arc.move(to: CGPoint(x: c.x - 13, y: c.y + 5))
            arc.addQuadCurve(to: CGPoint(x: c.x + 13, y: c.y + 5), control: CGPoint(x: c.x, y: c.y - 13))
            happy.stroke(arc, with: .color(C.outline), style: Self.outline(5))
        }
    }

    private func drawBrows(_ gc: GraphicsContext) {
        let left = Self.transformed(gc, pivot: CGPoint(x: 92, y: 66), y: pose.browLeftY, rotate: pose.browLeftRotate)
        left.stroke(OwlPaths.browLeft, with: .color(C.brow), style: Self.outline(5))
        let right = Self.transformed(gc, pivot: CGPoint(x: 148, y: 66), y: pose.browRightY, rotate: pose.browRightRotate)
        right.stroke(OwlPaths.browRight, with: .color(C.brow), style: Self.outline(5))
    }

    private func drawBeak(_ gc: GraphicsContext) {
        if pose.mouthScaleY > 0.001 {
            let mouth = Self.transformed(gc, pivot: CGPoint(x: 120, y: 128), scaleY: pose.mouthScaleY)
            mouth.fill(Self.ellipse(120, 139, 10.5, 12), with: .color(C.mouth))
            mouth.fill(Self.ellipse(120, 147, 6, 3.6), with: .color(C.tongue))
        }
        let lower = Self.transformed(gc, pivot: .zero, y: pose.lowerBeakY)
        lower.fill(OwlPaths.lowerBeak, with: .color(C.beakShade))
        lower.stroke(OwlPaths.lowerBeak, with: .color(C.outline), style: Self.outline(2.5))

        gc.fill(OwlPaths.upperBeak, with: .color(C.beak))
        gc.stroke(OwlPaths.upperBeak, with: .color(C.outline), style: Self.outline(2.5))
        var shine = gc
        shine.opacity = 0.55
        shine.stroke(OwlPaths.beakShine, with: .color(.white), style: Self.outline(2.2))
    }

    private func drawQuestion(_ gc: GraphicsContext) {
        guard pose.questionOpacity > 0.001, pose.questionScale > 0.001 else { return }
        var g = Self.transformed(
            gc, pivot: CGPoint(x: 206, y: 44), y: pose.questionY,
            scaleX: pose.questionScale, scaleY: pose.questionScale, rotate: pose.questionRotate
        )
        g.opacity = pose.questionOpacity
        g.stroke(OwlPaths.questionHook, with: .color(C.accent), style: Self.outline(6.5))
        g.fill(Self.ellipse(206, 62, 4.2, 4.2), with: .color(C.accent))
    }

    private func drawThoughtDots(_ gc: GraphicsContext) {
        let dots: [(CGFloat, CGFloat, CGFloat)] = [(196, 50, 4), (208, 36, 5.5), (222, 20, 7)]
        for (i, dot) in dots.enumerated() where pose.dotOpacity[i] > 0.001 && pose.dotScale[i] > 0.001 {
            var g = Self.transformed(
                gc, pivot: CGPoint(x: dot.0, y: dot.1),
                scaleX: pose.dotScale[i], scaleY: pose.dotScale[i]
            )
            g.opacity = pose.dotOpacity[i]
            g.fill(Self.ellipse(dot.0, dot.1, dot.2, dot.2), with: .color(C.wing))
        }
    }

    private func drawSparkles(_ gc: GraphicsContext) {
        let sparkles: [(CGFloat, CGFloat, CGFloat)] = [(34, 64, 10), (210, 58, 12), (26, 150, 7), (216, 146, 8)]
        for (i, s) in sparkles.enumerated() where pose.sparkleOpacity[i] > 0.001 && pose.sparkleScale[i] > 0.001 {
            var g = Self.transformed(
                gc, pivot: CGPoint(x: s.0, y: s.1),
                scaleX: pose.sparkleScale[i], scaleY: pose.sparkleScale[i], rotate: pose.sparkleRotate[i]
            )
            g.opacity = pose.sparkleOpacity[i]
            g.fill(OwlPaths.sparkle(x: s.0, y: s.1, r: s.2), with: .color(C.sparkle))
        }
    }

    // MARK: Helpers

    /// Applies a transform around a pivot in the same order as the CSS
    /// transforms framer-motion writes: translate, then scale, then rotate.
    private static func transformed(
        _ gc: GraphicsContext,
        pivot: CGPoint,
        x: Double = 0,
        y: Double = 0,
        scaleX: Double = 1,
        scaleY: Double = 1,
        rotate: Double = 0
    ) -> GraphicsContext {
        var g = gc
        g.translateBy(x: pivot.x + x, y: pivot.y + y)
        g.scaleBy(x: scaleX, y: scaleY)
        g.rotate(by: .degrees(rotate))
        g.translateBy(x: -pivot.x, y: -pivot.y)
        return g
    }

    /// Mirrors left-side art onto the right side of the design space.
    private static func mirrored(_ gc: GraphicsContext) -> GraphicsContext {
        var g = gc
        g.concatenate(mirror)
        return g
    }

    private static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    private static func outline(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }
}

// MARK: - Paths

/// Path data translated one to one from the SVG in components/pip/Owl.tsx.
private enum OwlPaths {
    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    /// M58 76 C50 62 42 46 36 28 C46 32 54 37 60 42 C60 36 61 31 64 26 C74 34 86 41 98 46 Z
    static var tuft: Path {
        Path { path in
            path.move(to: p(58, 76))
            path.addCurve(to: p(36, 28), control1: p(50, 62), control2: p(42, 46))
            path.addCurve(to: p(60, 42), control1: p(46, 32), control2: p(54, 37))
            path.addCurve(to: p(64, 26), control1: p(60, 36), control2: p(61, 31))
            path.addCurve(to: p(98, 46), control1: p(74, 34), control2: p(86, 41))
            path.closeSubpath()
        }
    }

    /// M54 56 C50 49 47 43 44 37
    static var tuftStreak: Path {
        Path { path in
            path.move(to: p(54, 56))
            path.addCurve(to: p(44, 37), control1: p(50, 49), control2: p(47, 43))
        }
    }

    /// M80 138 C58 140 42 160 42 186 C42 198 46 208 52 214 C54 206 58 206 60 212
    /// C62 204 67 204 69 209 C76 192 82 170 82 148 Z
    static var wing: Path {
        Path { path in
            path.move(to: p(80, 138))
            path.addCurve(to: p(42, 186), control1: p(58, 140), control2: p(42, 160))
            path.addCurve(to: p(52, 214), control1: p(42, 198), control2: p(46, 208))
            path.addCurve(to: p(60, 212), control1: p(54, 206), control2: p(58, 206))
            path.addCurve(to: p(69, 209), control1: p(62, 204), control2: p(67, 204))
            path.addCurve(to: p(82, 148), control1: p(76, 192), control2: p(82, 170))
            path.closeSubpath()
        }
    }

    /// M70 156 C62 168 58 182 58 196
    static var wingFeather1: Path {
        Path { path in
            path.move(to: p(70, 156))
            path.addCurve(to: p(58, 196), control1: p(62, 168), control2: p(58, 182))
        }
    }

    /// M76 162 C72 174 69 186 68 198
    static var wingFeather2: Path {
        Path { path in
            path.move(to: p(76, 162))
            path.addCurve(to: p(68, 198), control1: p(72, 174), control2: p(69, 186))
        }
    }

    /// M120 38 C163 38 192 64 192 100 C192 138 160 158 120 158 C80 158 48 138 48 100
    /// C48 64 77 38 120 38 Z
    static var head: Path {
        Path { path in
            path.move(to: p(120, 38))
            path.addCurve(to: p(192, 100), control1: p(163, 38), control2: p(192, 64))
            path.addCurve(to: p(120, 158), control1: p(192, 138), control2: p(160, 158))
            path.addCurve(to: p(48, 100), control1: p(80, 158), control2: p(48, 138))
            path.addCurve(to: p(120, 38), control1: p(48, 64), control2: p(77, 38))
            path.closeSubpath()
        }
    }

    /// M101 170 q5 5 10 0 (and the five matching marks below it)
    static var bellyMarks: Path {
        Path { path in
            let starts: [(CGFloat, CGFloat)] = [
                (101, 170), (115, 170), (129, 170),
                (108, 184), (122, 184),
                (115, 198),
            ]
            for (x, y) in starts {
                path.move(to: p(x, y))
                path.addQuadCurve(to: p(x + 10, y), control: p(x + 5, y + 5))
            }
        }
    }

    /// M79 69 Q92 61 105 66
    static var browLeft: Path {
        Path { path in
            path.move(to: p(79, 69))
            path.addQuadCurve(to: p(105, 66), control: p(92, 61))
        }
    }

    /// M161 69 Q148 61 135 66
    static var browRight: Path {
        Path { path in
            path.move(to: p(161, 69))
            path.addQuadCurve(to: p(135, 66), control: p(148, 61))
        }
    }

    /// M112.5 130 C114 137 117 140 120 140 C123 140 126 137 127.5 130 Z
    static var lowerBeak: Path {
        Path { path in
            path.move(to: p(112.5, 130))
            path.addCurve(to: p(120, 140), control1: p(114, 137), control2: p(117, 140))
            path.addCurve(to: p(127.5, 130), control1: p(123, 140), control2: p(126, 137))
            path.closeSubpath()
        }
    }

    /// M106 116 C112 110 128 110 134 116 C131 125 125 132 120 138 C115 132 109 125 106 116 Z
    static var upperBeak: Path {
        Path { path in
            path.move(to: p(106, 116))
            path.addCurve(to: p(134, 116), control1: p(112, 110), control2: p(128, 110))
            path.addCurve(to: p(120, 138), control1: p(131, 125), control2: p(125, 132))
            path.addCurve(to: p(106, 116), control1: p(115, 132), control2: p(109, 125))
            path.closeSubpath()
        }
    }

    /// M112 117 C116 115 121 115 124 116
    static var beakShine: Path {
        Path { path in
            path.move(to: p(112, 117))
            path.addCurve(to: p(124, 116), control1: p(116, 115), control2: p(121, 115))
        }
    }

    /// M197 34 C197 22 215 21 215 33 C215 42 206 42 206 51
    static var questionHook: Path {
        Path { path in
            path.move(to: p(197, 34))
            path.addCurve(to: p(215, 33), control1: p(197, 22), control2: p(215, 21))
            path.addCurve(to: p(206, 51), control1: p(215, 42), control2: p(206, 42))
        }
    }

    /// A four point star made of quadratic curves pinched toward the center.
    static func sparkle(x: CGFloat, y: CGFloat, r: CGFloat) -> Path {
        let k = r * 0.28
        return Path { path in
            path.move(to: p(x, y - r))
            path.addQuadCurve(to: p(x + r, y), control: p(x + k, y - k))
            path.addQuadCurve(to: p(x, y + r), control: p(x + k, y + k))
            path.addQuadCurve(to: p(x - r, y), control: p(x - k, y + k))
            path.addQuadCurve(to: p(x, y - r), control: p(x - k, y - k))
            path.closeSubpath()
        }
    }
}
