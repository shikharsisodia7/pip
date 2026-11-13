import SwiftUI
import PipKit

struct PipReadsScreen: View {
    @Environment(Session.self) private var session

    var body: some View {
        StubScreen(title: "Pip reads to you", note: "Listen closely. Can you catch Pip's mistake?") {
            session.advance()
        }
    }
}
