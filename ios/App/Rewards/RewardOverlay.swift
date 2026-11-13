import SwiftUI
import PipKit

/// "+N stars" toast on every award, and a bigger card when Pip levels up.
/// Disappears after about 2 seconds or on tap, so it never blocks the flow.
struct RewardOverlay: View {
    @Environment(Session.self) private var session

    private struct Toast: Equatable {
        let id: Int
        let gain: Int
        let reason: String
        let newStage: String?
    }

    @State private var toast: Toast?
    @State private var lastStage = 1

    var body: some View {
        ZStack {
            if let t = toast {
                VStack(spacing: 10) {
                    if let stage = t.newStage {
                        PipView(state: .celebrating, size: 110)
                        Text("Pip grew! \(stage) Pip")
                            .font(.pip(30, .bold))
                            .foregroundStyle(Palette.text)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill").foregroundStyle(Palette.sun)
                        Text("+\(t.gain)").foregroundStyle(Palette.sun)
                    }
                    .font(.pip(t.newStage == nil ? 30 : 24, .bold))
                    Text(t.reason)
                        .font(.pip(18, .semibold))
                        .foregroundStyle(Palette.textSoft)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .background(Palette.surfaceHigh.opacity(0.95), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Palette.stroke))
                .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .onTapGesture { withAnimation { toast = nil } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: session.rewards.gainCount) { show() }
    }

    private func show() {
        let r = session.rewards
        guard r.gainCount > 0 else { lastStage = 1; return }
        let leveled = r.stage > lastStage
        lastStage = r.stage
        let t = Toast(id: r.gainCount, gain: r.lastGain, reason: r.lastEvent?.reason ?? "",
                      newStage: leveled ? r.stageName : nil)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { toast = t }
        Task {
            try? await Task.sleep(for: .seconds(leveled ? 2.4 : 1.6))
            if toast?.id == t.id { withAnimation { toast = nil } }
        }
    }
}
