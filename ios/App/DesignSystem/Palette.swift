import SwiftUI

/// A dark indigo world with bright, friendly accents.
/// `paper` and `ink` are reserved for the story page card so story text stays very readable.
/// Never red, including for errors.
enum Palette {
    static let bgTop = Color(hex: 0x2B2F77)
    static let bgBottom = Color(hex: 0x161A45)
    static let backgroundGradient = LinearGradient(
        colors: [bgTop, bgBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    static let surface = Color(hex: 0x2F3480)
    static let surfaceHigh = Color(hex: 0x3A3F96)
    static let stroke = Color.white.opacity(0.10)

    static let text = Color.white
    static let textSoft = Color(hex: 0xB9BCF0)

    static let accent = Color(hex: 0x3DB4F2)
    static let accentDeep = Color(hex: 0x1F7FC0)
    static let sun = Color(hex: 0xFFC845)
    static let pink = Color(hex: 0xFF7AA8)
    static let mint = Color(hex: 0x5EE0B0)
    static let purple = Color(hex: 0x9B7BFF)
    static let orange = Color(hex: 0xFF9F43)

    /// Story page card only.
    static let paper = Color(hex: 0xFFF7EA)
    static let ink = Color(hex: 0x2B2118)
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
    /// Full-bleed indigo gradient behind a screen.
    func pipBackground() -> some View {
        background(Palette.backgroundGradient.ignoresSafeArea())
    }
}
