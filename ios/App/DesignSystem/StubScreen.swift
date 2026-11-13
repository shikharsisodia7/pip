import SwiftUI

/// Placeholder screen used by phase stubs until their owners replace them.
struct StubScreen: View {
    private let title: String
    private let note: String
    private let nextLabel: String
    private let action: () -> Void

    init(title: String, note: String, nextLabel: String = "Next", action: @escaping () -> Void) {
        self.title = title
        self.note = note
        self.nextLabel = nextLabel
        self.action = action
    }

    var body: some View {
        VStack(spacing: 28) {
            Card(padding: 28) {
                VStack(spacing: 10) {
                    Text("PLACEHOLDER SCREEN")
                        .font(.pip(13, .bold))
                        .tracking(2)
                        .foregroundStyle(Palette.mint)
                    Text(title)
                        .font(.pip(34, .bold))
                        .foregroundStyle(Palette.text)
                        .multilineTextAlignment(.center)
                    Text(note)
                        .font(.pip(19))
                        .foregroundStyle(Palette.textSoft)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 560)
            }
            BigButton(nextLabel, action: action)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pipBackground()
    }
}
