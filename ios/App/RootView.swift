// Home tabs when no session is running; otherwise the current step of the
// reading session. Reward toasts float above everything.

import SwiftUI
import PipKit

struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        ZStack {
            PipBackdrop().ignoresSafeArea()

            screen
                .id(session.phase)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))

            if [.pipReads, .expression, .probePre, .probePost].contains(session.phase) {
                OrbButton(systemImage: "xmark", colors: Palette.blueOrb, size: 40) {
                    PipPlayer.shared.stop()
                    session.reset()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 16)
                .padding(.top, 4)
            }

            RewardOverlay()
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: session.phase)
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .debugHotZone()
        .listenTestAction()
        .task {
            let book = await (try? API.current.book()) ?? .placeholder
            Library.shared.setFeatured(book)
            if session.phase == .intro { session.book = book }
            #if DEBUG
            // Screenshot and QA helper: launch with `-PipOpen read|report|pip|expression`.
            switch UserDefaults.standard.string(forKey: "PipOpen") {
            case "read": session.startReading(Library.shared.books[1])
            case "report": session.startReading(Library.shared.books[1]); session.goto(.report)
            case "pip": session.startReading(Library.shared.books[1]); session.goto(.pipReads)
            case "expression": session.startReading(Library.shared.books[1]); session.goto(.expression)
            default: break
            }
            #endif
        }
    }

    @ViewBuilder private var screen: some View {
        switch session.phase {
        case .intro: IntroScreen()
        case .probePre: ProbeScreen(kind: .pre)
        case .read: ReadScreen()
        case .pipReads: PipReadsScreen()
        case .expression: ExpressionScreen()
        case .probePost: ProbeScreen(kind: .post)
        case .report: ReportScreen()
        }
    }
}
