// FROZEN. Shows the screen for the current phase over the shared background,
// with the reward HUD on top and the hidden debug panel in the corner.

import SwiftUI
import PipKit

struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        ZStack {
            Palette.backgroundGradient.ignoresSafeArea()

            screen
                .id(session.phase)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))

            RewardHUD()
            RewardOverlay()
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: session.phase)
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .debugHotZone()
        .task { session.book = await (try? API.current.book()) ?? .placeholder }
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
