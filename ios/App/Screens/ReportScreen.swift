import SwiftUI
import PipKit

struct ReportScreen: View {
    @Environment(Session.self) private var session
    @State private var showPractice = false

    var body: some View {
        StubScreen(title: "What Pip learned from today's reading",
                   note: "The parent report goes here.", nextLabel: "Pip's Practice Book") {
            showPractice = true
        }
        .sheet(isPresented: $showPractice) { PracticeScreen().environment(session) }
    }
}
