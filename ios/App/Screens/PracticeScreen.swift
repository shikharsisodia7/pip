import SwiftUI
import PipKit

struct PracticeScreen: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        StubScreen(title: "Pip's Practice Book", note: "Six practice sentences for the tricky sound.",
                   nextLabel: "Start over") {
            dismiss()
            session.reset()
        }
    }
}
