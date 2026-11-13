import SwiftUI

/// Deep indigo night with glassy cards and candy-bright accents.
/// `paper` and `ink` are reserved for story text so it stays very readable.
enum Palette {
    static let bgTop = Color(hex: 0x30357E)
    static let bgBottom = Color(hex: 0x171A44)
    static let backgroundGradient = LinearGradient(
        colors: [bgTop, Color(hex: 0x232761), bgBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    static let surface = Color(hex: 0x2B3075)
    static let surfaceHigh = Color(hex: 0x3A3F96)
    static let stroke = Color.white.opacity(0.12)
    static let glass = Color.white.opacity(0.08)

    static let text = Color.white
    static let textSoft = Color(hex: 0xB9BCF0)

    static let accent = Color(hex: 0x3DB4F2)
    static let accentDeep = Color(hex: 0x1F7FC0)
    static let sun = Color(hex: 0xFFC845)
    static let pink = Color(hex: 0xFF7AA8)
    static let mint = Color(hex: 0x5EE0B0)
    static let purple = Color(hex: 0x9B7BFF)
    static let orange = Color(hex: 0xFF9F43)
    static let coral = Color(hex: 0xFF6B6B)

    /// Story page card only.
    static let paper = Color(hex: 0xFFF7EA)
    static let ink = Color(hex: 0x2B2118)

    // Card gradients, top-leading to bottom-trailing.
    static let oceanCard = [Color(hex: 0x3BA7E8), Color(hex: 0x2A5DB8)]
    static let grapeCard = [Color(hex: 0x6E4BD8), Color(hex: 0x3F2C93)]
    static let berryCard = [Color(hex: 0xD6559B), Color(hex: 0x7A2E86)]
    static let lagoonCard = [Color(hex: 0x2BB7A9), Color(hex: 0x1D6E8F)]
    static let sunsetCard = [Color(hex: 0xFFA24C), Color(hex: 0xD9534F)]
    static let cardGradients = [grapeCard, lagoonCard, berryCard, sunsetCard, oceanCard]

    // Round icon fills.
    static let blueOrb = [Color(hex: 0x52C4FF), Color(hex: 0x2A7BE0)]
    static let purpleOrb = [Color(hex: 0xA889FF), Color(hex: 0x6A47D6)]
    static let pinkOrb = [Color(hex: 0xFF8FC0), Color(hex: 0xD64F8F)]
    static let orangeOrb = [Color(hex: 0xFFC163), Color(hex: 0xF07A2C)]
    static let mintOrb = [Color(hex: 0x7BF0C4), Color(hex: 0x23A884)]
}

extension Color {
    /// 0xRRGGBB
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    /// "#e6ebff", "e6ebff" or "#fff". Returns nil for anything else.
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(hex: value)
    }
}

extension View {
    /// Full-bleed indigo gradient behind a screen, with two soft color glows.
    func pipBackground() -> some View {
        background(PipBackdrop().ignoresSafeArea())
    }
}

/// The app backdrop: indigo gradient with faint purple and blue glows.
struct PipBackdrop: View {
    var body: some View {
        ZStack {
            Palette.backgroundGradient
            // Full-size radial gradients rather than blurred circles: the same
            // glow, drawn once instead of filtered on every frame, and they
            // never change the layout size.
            RadialGradient(colors: [Palette.purple.opacity(0.25), .clear],
                           center: UnitPoint(x: 0.1, y: 0.16), startRadius: 0, endRadius: 330)
            RadialGradient(colors: [Palette.accent.opacity(0.18), .clear],
                           center: UnitPoint(x: 0.95, y: 0.87), startRadius: 0, endRadius: 310)
        }
    }
}
