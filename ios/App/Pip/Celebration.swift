import SwiftUI

/// A short burst of confetti stars.
struct Celebration: View {
    @State private var go = false
    private let colors = [Palette.sun, Palette.pink, Palette.mint, Palette.accent, Palette.purple, Palette.orange]

    var body: some View {
        ZStack {
            ForEach(0..<18, id: \.self) { i in
                Image(systemName: i.isMultiple(of: 2) ? "star.fill" : "circle.fill")
                    .font(.system(size: i.isMultiple(of: 2) ? 22 : 12))
                    .foregroundStyle(colors[i % colors.count])
                    .offset(x: go ? cos(Double(i) / 18 * 2 * .pi) * 220 : 0,
                            y: go ? sin(Double(i) / 18 * 2 * .pi) * 160 : 0)
                    .opacity(go ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 1.2)) { go = true } }
    }
}
