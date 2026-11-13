import SwiftUI

/// What Pip is saying, in a rounded bubble.
struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.pip(24, .semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }
}
