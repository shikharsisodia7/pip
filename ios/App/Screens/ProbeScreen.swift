import SwiftUI
import PipKit

struct ProbeScreen: View {
    @Environment(Session.self) private var session
    let kind: ProbeKind

    var body: some View {
        StubScreen(title: kind == .pre ? "Warm up words" : "One more word check",
                   note: "Five quick words before and after the story.") {
            session.award(.probeFinished)
            session.advance()
        }
    }
}
