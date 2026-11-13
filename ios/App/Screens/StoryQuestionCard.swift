// Pip asks one question about the page, the child answers by voice, and Pip
// responds kindly. Never framed as wrong: a miss ends with Pip sharing the answer.
// The mic never opens while Pip is talking.

import SwiftUI
import PipKit

struct StoryQuestionCard: View {
    let question: StoryQuestion
    let onComplete: (AnswerVerdict, Int) -> Void

    private enum Phase { case asking, ready, listening, responding, done }

    @State private var phase: Phase = .asking
    @State private var tries = 0
    @State private var listener: (any Listening)?
    @State private var stopRequested = false
    @State private var heard = ""
    @State private var confetti = 0

    private let listenSeconds = 6.0
    private var log: ComprehensionLog { .shared }

    var body: some View {
        GlassCard(colors: Palette.oceanCard, radius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Orb(systemImage: "questionmark", colors: Palette.orangeOrb, size: 46)
                    Text(question.question)
                        .font(.pip(24, .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !heard.isEmpty {
                    Text("\u{201C}\(heard)\u{201D}")
                        .font(.pip(16, .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                if phase != .done {
                    HStack(spacing: 16) {
                        MicButton(state: phase == .listening ? .listening : (phase == .ready ? .idle : .disabled),
                                  label: phase == .listening ? "Tap when you're done" : (phase == .ready ? "Tell Pip" : "Pip is talking"),
                                  size: 76) {
                            if phase == .listening { stopRequested = true } else if phase == .ready { Task { await listen() } }
                        }
                        Spacer()
                        Button("Skip") { finish(.noAnswer, skipped: true) }
                            .font(.pip(15, .bold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay { if confetti > 0 { Celebration().id(confetti) } }
        .task { await ask() }
        // Debug panel answers arrive while a sheet is open, so poll for them
        // instead of relying only on a change notification.
        .task(id: phase == .ready) {
            while !Task.isCancelled, phase == .ready {
                if log.injectedAnswer != nil { await judge(transcript: ""); break }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .onChange(of: log.injectedAnswer) { _, answer in
            guard answer != nil else { return }
            if phase == .listening { stopRequested = true }
            else if phase == .ready { Task { await judge(transcript: "") } }
        }
        .onDisappear {
            if let l = listener { Task { _ = await l.stop() } }
        }
    }

    // MARK: Flow

    private func say(_ text: String) async {
        await PipPlayer.shared.speak(.expressive(text), onWord: nil)
    }

    private func ask() async {
        phase = .asking
        await say("[curious] " + question.question)
        if phase == .asking { phase = .ready }
    }

    private func listen() async {
        while PipPlayer.shared.isSpeaking { try? await Task.sleep(for: .milliseconds(100)) }
        stopRequested = false
        heard = ""
        let l = Listeners.make()
        listener = l
        phase = .listening
        await l.start()
        let start = Date()
        while !Task.isCancelled, !stopRequested, log.injectedAnswer == nil, Date().timeIntervalSince(start) < listenSeconds {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let t = await l.stop()
        listener = nil
        await judge(transcript: t.text)
    }

    private func judge(transcript: String) async {
        let text = log.injectedAnswer ?? transcript
        log.injectedAnswer = nil
        heard = text
        tries += 1
        phase = .responding
        let verdict = judgeAnswer(text, for: question)
        switch verdict {
        case .correct:
            confetti += 1
            await say("[excited] Yes! " + question.answerLine)
            finish(.correct)
        case .close where tries < 2, .tryAgain where tries < 2:
            await say("[thoughtful] Hmm, almost. " + question.hint)
            phase = .ready
        default:
            await say("[warm] That's okay! " + question.answerLine)
            finish(verdict)
        }
    }

    /// Reports the result. A skip reports 0 tries so it is not counted as asked.
    private func finish(_ verdict: AnswerVerdict, skipped: Bool = false) {
        guard phase != .done else { return }
        phase = .done
        PipPlayer.shared.stop()
        if let l = listener { Task { _ = await l.stop() } }
        listener = nil
        onComplete(verdict, skipped ? 0 : max(tries, 1))
    }
}
