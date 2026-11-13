import SwiftUI
import PipKit

/// Star count and progress to Pip's next look, pinned top right.
struct RewardHUD: View {
    @Environment(Session.self) private var session

    var body: some View {
        let r = session.rewards
        HStack(spacing: 10) {
            Image(systemName: "star.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.sun)
                .symbolEffect(.bounce, value: r.gainCount)
            Text("\(r.stars)")
                .font(.pip(22, .bold))
                .foregroundStyle(Palette.text)
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 3) {
                Text(r.stageName)
                    .font(.pip(12, .bold))
                    .foregroundStyle(Palette.textSoft)
                Meter(value: r.stageProgress, tone: .sun, height: 8)
                    .frame(width: 90)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Palette.stroke))
        .animation(.spring, value: r.stars)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(16)
        .allowsHitTesting(false)
    }
}
