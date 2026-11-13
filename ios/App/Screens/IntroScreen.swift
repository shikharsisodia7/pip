import SwiftUI
import PipKit

struct IntroScreen: View {
    @Environment(Session.self) private var session

    var body: some View {
        HStack(spacing: 40) {
            PipView(state: .idle, size: 200)
            VStack(alignment: .leading, spacing: 18) {
                Text("Hi! I'm Pip.")
                    .font(.pip(46, .bold))
                    .foregroundStyle(Palette.text)
                Text("Will you read me a story? I'm still learning to read.")
                    .font(.pip(22))
                    .foregroundStyle(Palette.textSoft)
                Card(padding: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.book.title)
                            .font(.pip(28, .bold))
                            .foregroundStyle(Palette.text)
                        StoryCredit(book: session.book)
                    }
                }
                BigButton("Let's read!", systemImage: "book.fill") { session.advance() }
            }
            .frame(maxWidth: 480)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
