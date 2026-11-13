import SwiftUI
import PipKit

@main
struct PipApp: App {
    @State private var session = Session()

    init() {
        AudioSessionManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(Settings.shared)
        }
    }
}
