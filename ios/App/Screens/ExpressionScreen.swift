// The expression moment. Pip reads an emotional line flat and asks how it
// should sound. The child performs it while their voice draws a live pitch
// line over Pip's flat one. If they are clearly more expressive than their own
// reading baseline, Pip learns it and performs the line with feeling.

import SwiftUI
import PipKit

struct ExpressionScreen: View {
    @Environment(Session.self) private var session

    private enum Stage: Equatable {
        case loading, pipFlat, asking, ready, recording, scoring, retry, learning, learned, practicing
    }

    @State private var stage: Stage = .loading
    @State private var lit = -1
    @State private var bubble = ""
    @State private var frames: [ProsodyFrame] = []
    @State private var attempts = 0
    @State private var score: Double?
    @State private var confetti = 0
    @State private var tagged: ExpressionTags?
    @State private var recorder: ProsodyRecorder?
    @State private var lastStats: ProsodyStats?
    @State private var unregister: [@MainActor () -> Void] = []
    @State private var autoStop: Task<Void, Never>?

    private let maxFailedTries = 2

    private var line: EmotionLine {
        if let l = session.pipPage?.emotionLine { return l }
        if let l = session.book.pages.first(where: { $0.emotionLine != nil })?.emotionLine { return l }
        return EmotionLine(text: "Oh no! What was that?", speaker: nil, emotion: .scared)
    }
    private var context: String { session.pipPage?.text ?? "" }
    private var words: [String] { line.text.split(whereSeparator: { $0.isWhitespace }).map(String.init) }
    private var threshold: Double { Settings.shared.expressionThreshold }

    private var hint: (icon: String, word: String) {
        switch line.emotion {
        case .scared: return ("😨", "scared")
        case .excited: return ("🤩", "excited")
        case .sad: return ("😢", "sad")
        case .whispering: return ("🤫", "whispering")
        case .shouting: return ("📣", "shouting")
        case .happy: return ("😊", "happy")
        case .angry: return ("😠", "angry")
        }
    }

    private var pipBusy: Bool { [.loading, .pipFlat, .asking, .retry, .learning, .scoring].contains(stage) }
    private var done: Bool { stage == .learned || stage == .practicing }
    private var learned: Bool { stage == .learned || stage == .learning }

    private var pipState: PipState {
        switch stage {
        case .learning: return .speaking
        case .learned: return .celebrating
        case .retry: return .confused
        case .recording: return .listening
        case .scoring, .loading: return .thinking
        case .pipFlat, .asking: return .speaking
        default: return .idle
        }
    }

    private var meterValue: Double {
        if learned { return 1 }
        guard let score else { return 0 }
        return min(0.95, score / (threshold * 1.15))
    }

    private var prompt: String {
        switch stage {
        case .ready:
            return attempts == 0 ? "Your turn! Say it the way \(line.speaker ?? "they") would."
                                 : "Try again! Make it sound really \(hint.word)."
        case .recording: return "Pip is listening to how it sounds..."
        case .practicing: return "Pip will keep practicing. Great teaching!"
        case .learned: return "You taught Pip how it feels!"
        default: return ""
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 16) {
                    pip
                    lineCard
                        .padding(.trailing, 190) // leaves room for the star counter
                }
                PitchContourView(frames: frames, active: stage == .recording)
                    .frame(minHeight: 110, maxHeight: .infinity)
                controls
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)

            if confetti > 0 {
                Celebration().id(confetti)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await intro() }
        .onAppear(perform: registerDebug)
        .onDisappear {
            unregister.forEach { $0() }
            autoStop?.cancel()
            PipPlayer.shared.stop()
            _ = recorder?.stop()
        }
    }

    // MARK: Pieces

    private var pip: some View {
        ZStack(alignment: .top) {
            PipView(state: pipState, size: 110)
                .padding(.top, 30)
            if pipBusy, !bubble.isEmpty, bubble != line.text {
                SpeechBubble(text: bubble)
                    .frame(width: 230)
                    .offset(x: 70, y: -8)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .frame(width: 150)
        .animation(.spring(duration: 0.3), value: bubble)
    }

    private var lineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let s = line.speaker {
                    Text("\(s) says:").font(.pip(18, .semibold)).foregroundStyle(Palette.ink.opacity(0.6))
                }
                HStack(spacing: 6) {
                    Text(hint.icon)
                    Text("Feeling: ").foregroundStyle(Palette.ink.opacity(0.6)) + Text(hint.word).bold()
                }
                .font(.pip(16))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.white, in: Capsule())
                Spacer()
            }
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                    Text(w)
                        .font(.pip(34, .bold))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(stage == .pipFlat && i <= lit ? Palette.sun.opacity(i == lit ? 1 : 0.4) : .clear)
                        )
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if learned {
                Text("Pip learned it!")
                    .font(.pip(22, .bold))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Palette.sun, in: Capsule())
                    .rotationEffect(.degrees(-4))
                    .offset(x: 8, y: -16)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: learned)
    }

    private var controls: some View {
        HStack(spacing: 20) {
            Meter(value: meterValue, label: "Feeling", tone: learned ? .sun : .accent, height: 16)
                .frame(width: 220)
            Text(prompt)
                .font(.pip(20, .semibold))
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            if done {
                if stage == .learned {
                    BigButton("Hear Pip again", variant: .secondary, systemImage: "speaker.wave.2.fill") {
                        Task { await readExpressive() }
                    }
                }
                BigButton("Next", systemImage: "arrow.right") { session.advance() }
            } else {
                MicButton(state: stage == .recording ? .listening : (stage == .ready ? .idle : .disabled),
                          label: stage == .recording ? "Tap when you finish" : (stage == .ready ? "Say it with feeling" : "Pip is talking"),
                          size: 80) {
                    if stage == .recording { Task { await stopRecording() } } else if stage == .ready { startRecording() }
                }
                BigButton("Skip", variant: .quiet) { session.advance() }
            }
        }
    }

    // MARK: Flow

    private func say(_ l: PipLine) async {
        bubble = l.text
        await PipPlayer.shared.speak(.expressive(l.tagged), onWord: nil)
    }

    private func readFlat() async {
        lit = -1
        bubble = line.text
        await PipPlayer.shared.speak(.flat(line.text)) { i in lit = i }
    }

    private func getTagged() async -> ExpressionTags {
        if let tagged { return tagged }
        let t = (try? await API.current.expressionTags(line: line, context: context))
            ?? ExpressionTags(taggedText: "[excited] \(line.text)", tags: ["excited"])
        tagged = t
        return t
    }

    private func readExpressive() async {
        let t = await getTagged()
        lit = -1
        bubble = line.text
        await PipPlayer.shared.speak(.expressive(t.taggedText), onWord: nil)
    }

    private func intro() async {
        let t = await getTagged()
        let lines: [TtsRequest] = [.flat(line.text), .expressive(t.taggedText)]
            + [PipLine.howShouldItSound, .likeThis, .showMeAgain, .keepPracticing].map { .expressive($0.tagged) }
        Task { await PipPlayer.shared.prefetch(lines) }
        guard !Task.isCancelled else { return }
        stage = .pipFlat
        await readFlat()
        guard !Task.isCancelled else { return }
        stage = .asking
        await say(.howShouldItSound)
        guard !Task.isCancelled else { return }
        stage = .ready
    }

    private func startRecording() {
        guard stage == .ready, !PipPlayer.shared.isSpeaking else { return } // mic never opens while Pip talks
        frames = []
        bubble = ""
        let rec = ProsodyRecorder()
        rec.onFrame = { f in frames.append(f) }
        recorder = rec
        rec.start()
        stage = .recording
        autoStop = Task {
            try? await Task.sleep(for: .seconds(7))
            if !Task.isCancelled, stage == .recording { await stopRecording() }
        }
    }

    private func stopRecording() async {
        guard let rec = recorder else { return }
        autoStop?.cancel()
        recorder = nil
        stage = .scoring
        let stats = rec.stop()
        lastStats = stats
        attempts += 1
        let result = expressionScore(attempt: stats, baseline: session.baselineProsody, threshold: threshold)
        score = result.score
        session.setDebug("expression.attempt", stats)
        session.setDebug("expression.score", String(format: "%.2f (threshold %.2f)", result.score, threshold))
        if result.passed { await learn(stats, result.score) } else { await notYet(stats, result.score) }
    }

    private func store(_ attempt: ProsodyStats, _ s: Double, passed: Bool) {
        session.expression = ExpressionResult(baseline: session.baselineProsody, attempt: attempt,
                                              score: (s * 100).rounded() / 100, passed: passed,
                                              attempts: attempts, tags: tagged?.tags ?? [])
    }

    private func learn(_ attempt: ProsodyStats, _ s: Double) async {
        store(attempt, s, passed: true)
        session.award(.expressionLearned)
        stage = .learning
        confetti += 1
        await say(.likeThis)
        await readExpressive()
        stage = .learned
    }

    private func notYet(_ attempt: ProsodyStats, _ s: Double) async {
        if attempts >= maxFailedTries {
            store(attempt, s, passed: false)
            stage = .practicing
            await say(.keepPracticing)
            return
        }
        stage = .retry
        await say(.showMeAgain)
        stage = .ready
    }

    // MARK: Debug

    private func registerDebug() {
        session.setDebug("expression.threshold", String(format: "%.2f", threshold))
        session.setDebug("expression.baseline", session.baselineProsody.map { "\($0)" } ?? "none")
        let showThreshold = { session.setDebug("expression.threshold", String(format: "%.2f", Settings.shared.expressionThreshold)) }
        unregister = [
            session.registerDebugAction("Force pass") {
                PipPlayer.shared.stop()
                let attempt = lastStats ?? ProsodyStats(pitchRangeSemitones: 12, pitchSdSemitones: 4, loudnessSdDb: 5, wordsPerSec: 3, voicedFrames: 80)
                attempts = max(1, attempts)
                let s = max(threshold, score ?? 0)
                score = s
                Task { await learn(attempt, s) }
            },
            session.registerDebugAction("Force fail") {
                PipPlayer.shared.stop()
                attempts += 1
                Task { await notYet(lastStats ?? .zero, 0) }
            },
            session.registerDebugAction("Replay flat") { Task { await readFlat() } },
            session.registerDebugAction("Replay expressive") { Task { await readExpressive() } },
            session.registerDebugAction("Threshold +0.05") {
                Settings.shared.expressionThreshold = normalizedExpressionThreshold(Settings.shared.expressionThreshold + 0.05)
                showThreshold()
            },
            session.registerDebugAction("Threshold -0.05") {
                Settings.shared.expressionThreshold = normalizedExpressionThreshold(Settings.shared.expressionThreshold - 0.05)
                showThreshold()
            },
        ]
    }
}
