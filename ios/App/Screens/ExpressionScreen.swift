import SwiftUI
import PipKit

struct ExpressionScreen: View {
    @Environment(Session.self) private var session

    var body: some View {
        StubScreen(title: "Read it with feeling", note: "Show Pip how Golu sounds when he is excited.") {
            session.advance()
        }
    }
}
