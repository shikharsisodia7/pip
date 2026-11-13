import SwiftUI

/// A short, warm two-sided confetti burst. Place it as an overlay that fills
/// the screen; it fires whenever `trigger` changes to a new value, never
/// blocks touches, and stays empty under Reduce Motion.
struct Celebration: View {
    private let trigger: Int

    init(trigger: Int) {
        self.trigger = trigger
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst: ConfettiBurst?

    var body: some View {
        ZStack {
            Color.clear
            if let burst, !reduceMotion {
                TimelineView(.animation) { context in
                    ConfettiCanvas(burst: burst, elapsed: context.date.timeIntervalSince(burst.start))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, newValue in
            guard !reduceMotion else { return }
            burst = ConfettiBurst(id: newValue, start: Date(), seed: UInt64.random(in: 1...UInt64.max))
        }
        .task(id: burst?.id) {
            guard burst != nil else { return }
            do { try await Task.sleep(for: .seconds(ConfettiBurst.totalDuration)) } catch { return }
            burst = nil
        }
    }
}

// MARK: - Particles

/// One burst: a fuller opening pop from each lower corner, then a short
/// stream for 1.2 seconds, as the web version does with canvas-confetti.
struct ConfettiBurst {
    let id: Int
    let start: Date
    let particles: [ConfettiParticle]

    static let streamDuration = 1.2
    static let particleLife = 2.2
    static var totalDuration: Double { streamDuration + particleLife }

    static let colors: [Color] = [0xF6A12E, 0xE5792B, 0xFFC23D, 0xF28B74, 0xC47A3F, 0xFFD166].map { hex in
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    init(id: Int, start: Date, seed: UInt64) {
        self.id = id
        self.start = start
        var rng = ConfettiRandom(seed: seed)
        var list: [ConfettiParticle] = []
        for fromRight in [false, true] {
            for _ in 0..<26 {
                list.append(ConfettiParticle(fromRight: fromRight, spawn: 0, rng: &rng))
            }
            // Three more per side every 50 ms for the rest of the stream.
            var spawn = 0.05
            while spawn < Self.streamDuration {
                for _ in 0..<3 {
                    list.append(ConfettiParticle(fromRight: fromRight, spawn: spawn, rng: &rng))
                }
                spawn += 0.05
            }
        }
        particles = list
    }
}

struct ConfettiParticle {
    let fromRight: Bool
    let spawn: Double
    /// Launch direction in radians, measured counterclockwise from the right.
    let angle: Double
    /// Launch speed relative to the base speed, from 0.5 to 1.5.
    let speed: Double
    let colorIndex: Int
    let isCircle: Bool
    let wobblePhase: Double
    let wobbleSpeed: Double
    let tiltPhase: Double
    let tiltSpeed: Double
    let size: Double

    init(fromRight: Bool, spawn: Double, rng: inout ConfettiRandom) {
        self.fromRight = fromRight
        self.spawn = spawn
        let base = fromRight ? 120.0 : 60.0
        let spread = 58.0
        angle = (base + (rng.next() - 0.5) * spread) * .pi / 180
        speed = 0.5 + rng.next()
        colorIndex = Int(rng.next() * Double(ConfettiBurst.colors.count)) % ConfettiBurst.colors.count
        isCircle = rng.next() < 0.5
        wobblePhase = rng.next() * 10
        wobbleSpeed = min(0.11, rng.next() * 0.1 + 0.05) * 60
        tiltPhase = (rng.next() * 0.5 + 0.25) * .pi
        tiltSpeed = (rng.next() * 2 - 1) * 6
        size = 7.5 + rng.next() * 3
    }
}

/// Small deterministic generator (SplitMix64) so a burst can be replayed.
struct ConfettiRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// A value in 0..<1.
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

// MARK: - Drawing

/// Draws a burst at a moment in time. Motion follows canvas-confetti: speed
/// decays by 10% per frame, gravity adds a steady fall, and each piece
/// wobbles and flips as it drifts.
struct ConfettiCanvas: View {
    let burst: ConfettiBurst
    let elapsed: Double

    /// Per second equivalent of canvas-confetti's 0.9 per frame decay at 60 fps.
    private static let decay = -log(0.9) * 60

    var body: some View {
        Canvas { context, size in
            let reach = 0.5 * (size.width * size.width + size.height * size.height).squareRoot()
            let fall = 0.2 * reach
            let originY = size.height * 0.75
            for particle in burst.particles {
                let age = elapsed - particle.spawn
                guard age >= 0, age < ConfettiBurst.particleLife else { continue }

                let travel = reach * particle.speed * (1 - exp(-Self.decay * age))
                let wobble = particle.wobblePhase + particle.wobbleSpeed * age
                let x = (particle.fromRight ? size.width : 0)
                    + cos(particle.angle) * travel + 10 * cos(wobble)
                let y = originY - sin(particle.angle) * travel + fall * age + 10 * sin(wobble) * 0.3

                var g = context
                g.opacity = max(0, min(1, 1 - (age - 0.9) / (ConfettiBurst.particleLife - 0.9)))
                g.translateBy(x: x, y: y)
                g.rotate(by: .radians(particle.tiltPhase + particle.tiltSpeed * age))
                g.scaleBy(x: 1, y: max(0.15, abs(cos(wobble))))
                let s = particle.size
                let rect = CGRect(x: -s / 2, y: -s / 2, width: s, height: s * (particle.isCircle ? 1 : 0.8))
                let shape = particle.isCircle ? Path(ellipseIn: rect) : Path(rect)
                g.fill(shape, with: .color(ConfettiBurst.colors[particle.colorIndex]))
            }
        }
    }
}
