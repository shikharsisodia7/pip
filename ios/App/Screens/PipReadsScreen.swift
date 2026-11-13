// "Your turn to be the teacher!" Pip reads the next page flat, with a planted
// mistake on a sound the child found tricky. He asks "Did I get that right?",
// the mic opens, and the child catches it by voice (or taps the word). After
// every catch Pip re-reads the whole sentence correctly, so the right model is
// always the last thing the child hears.

import SwiftUI
import PipKit

struct PipReadsScreen: View {
    @Environment(Session.self) private var session

    @State private var plan: PipPlan?
    @State private var lit: Set<Int> = []
    @State private var current = -1
    @State private var fixed: Set<Int> = []
    @State private var bubble = ""
    @State private var pipState: PipState = .thinking
    @State private var listener: (any Listening)?
    @State private var listening = false
    @State private var finished = false
    @State private var confetti = 0
    @State private var flip: Int?
    @State private var catches: [CatchResult] = []

    // Signals into the running sentence loop.
    @State private var tapCaught: Int?
    @State private var stopRequested = false
    @State private var skipRequested = false
    @State private var unregister: [@MainActor () -> Void] = []

    private let listenSeconds = 6.0

    private var page: BookPage? { session.pipPage }
    private var tokens: [Token] { tokenizeDisplay(page?.text ?? "") }

    var body: some View {
        ZStack {
            HStack(spacing: 22) {
                scene
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your turn to be the teacher!")
                        .font(.pip(28, .bold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.trailing, 200) // leaves room for the star counter
                    VStack(alignment: .leading, spacing: 14) {
                        words
                        StoryCredit(book: session.book, onPaper: true)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    controls
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)

            if confetti > 0 { Celebration().id(confetti) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await run() }
        .onAppear(perform: registerDebug)
        .onDisappear {
            unregister.forEach { $0() }
            PipPlayer.shared.stop()
            if let l = listener { Task { _ = await l.stop() } }
        }
    }

    // MARK: Pieces

    private var scene: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(hexString: page?.scene.bg ?? "") ?? Palette.surface)
            VStack {
                Spacer()
                Text(page?.scene.emoji ?? "📖").font(.system(size: 54)).opacity(0.85)
                PipView(state: pipState, size: 130)
                    .padding(.bottom, 12)
            }
            if !bubble.isEmpty {
                SpeechBubble(text: bubble)
                    .padding(10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 270)
        .animation(.spring(duration: 0.3), value: bubble)
    }

    private var words: some View {
        FlowLayout(spacing: 8, lineSpacing: 10) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { i, t in
                let m = mistake(at: i)
                let showMisread = m != nil && !fixed.contains(i) && sentenceStarted(m!.sentenceIndex)
                Button { tapped(i) } label: {
                    Text(showMisread ? misreadDisplay(t.display, m!.misread) : t.display)
                        .font(.pip(32, .semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(fixed.contains(i) ? Palette.mint.opacity(0.55)
                                      : lit.contains(i) ? Palette.sun.opacity(0.55) : .clear)
                        )
                        .overlay(alignment: .bottom) {
                            if showMisread {
                                Capsule().fill(Palette.orange).frame(height: 3).offset(y: 2)
                            }
                        }
                        .rotation3DEffect(.degrees(flip == i ? 360 : 0), axis: (x: 1, y: 0, z: 0))
                        .opacity(inCurrentSentence(i) || current < 0 ? 1 : 0.55)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            if listening {
                MicButton(state: .listening, label: "Tap when you finish", size: 76) { stopRequested = true }
                Text(listener?.partialText.isEmpty == false ? "\u{201C}\(listener!.partialText)\u{201D}" : "Pip is listening. Did he get it right?")
                    .font(.pip(20, .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
            } else if finished {
                Text("You're a great teacher!")
                    .font(.pip(22, .bold))
                    .foregroundStyle(Palette.text)
            } else {
                Text("Listen closely. You can tap a word Pip got wrong.")
                    .font(.pip(18))
                    .foregroundStyle(Palette.textSoft)
            }
            Spacer()
            if finished {
                BigButton("Next", systemImage: "arrow.right") { session.advance() }
            } else {
                BigButton("Skip", variant: .quiet) { session.advance() }
            }
        }
        .frame(minHeight: 80)
    }

    // MARK: Helpers

    private func mistake(at wordIndex: Int) -> PlantedMistake? {
        plan?.mistakes.first { $0.wordIndex == wordIndex }
    }

    private func sentenceStarted(_ s: Int) -> Bool { current >= s }

    private func inCurrentSentence(_ i: Int) -> Bool {
        guard let plan, plan.sentences.indices.contains(current) else { return false }
        let s = plan.sentences[current]
        return i >= s.wordStart && i < s.wordEnd
    }

    private func misreadDisplay(_ display: String, _ misread: String) -> String {
        // Keep the printed punctuation around the misread word.
        let lead = display.prefix { !$0.isLetter && !$0.isNumber }
        let trail = String(display.reversed().prefix { !$0.isLetter && !$0.isNumber }.reversed())
        return "\(lead)\(misread)\(trail)"
    }

    private func tapped(_ i: Int) {
        guard let m = mistake(at: i), !fixed.contains(i), sentenceStarted(m.sentenceIndex) else { return }
        tapCaught = i
        stopRequested = true
    }

    private func say(_ l: PipLine) async {
        bubble = l.text
        pipState = .speaking
        await PipPlayer.shared.speak(.expressive(l.tagged), onWord: nil)
    }

    private func readSentence(_ s: PipSentence, spoken: Bool) async {
        lit = []
        bubble = ""
        pipState = .speaking
        let text = spoken ? s.spokenText : s.text
        await PipPlayer.shared.speak(.flat(text)) { i in
            let idx = s.wordStart + i
            if idx < s.wordEnd { lit.insert(idx) }
        }
        pipState = .idle
    }

    // MARK: Flow

    private func loadPlan() async -> PipPlan? {
        guard let page else { return nil }
        let patterns = session.diagnosis?.patterns ?? []
        if let p = try? await API.current.pipMistakes(pageIndex: page.index, pageText: page.text, patterns: patterns) {
            return p
        }
        return try? API.fixture("pip-mistakes")
    }

    private func run() async {
        guard let p = await loadPlan() else { pipState = .idle; finished = true; return }
        plan = p
        session.pipPlan = p
        session.setDebug("pipReads.plan", p.mistakes.map { "\($0.correct) -> \($0.misread)" }.joined(separator: ", "))

        var prefetch: [TtsRequest] = p.sentences.map { .flat($0.spokenText) }
        for m in p.mistakes {
            prefetch.append(.flat(p.sentences[m.sentenceIndex].text))
            prefetch.append(.expressive(m.reaction))
        }
        prefetch += [PipLine.didIGetItRight, .whichWord, .mixedOneUp, .celebrate1].map { .expressive($0.tagged) }
        Task { await PipPlayer.shared.prefetch(prefetch) }

        // 2 minute path: only the sentence with the first mistake.
        let order: [Int]
        if session.demoPath == .twoMin, let first = p.mistakes.first {
            order = [first.sentenceIndex]
        } else {
            order = Array(p.sentences.indices)
        }

        for si in order {
            guard !Task.isCancelled else { return }
            current = si
            skipRequested = false
            let s = p.sentences[si]
            await readSentence(s, spoken: true)
            guard !Task.isCancelled else { return }
            if let m = p.mistakes.first(where: { $0.sentenceIndex == si }), !fixed.contains(m.wordIndex) {
                await teach(m, sentence: s)
            } else {
                try? await Task.sleep(for: .milliseconds(450))
            }
        }
        current = -1
        lit = []
        session.catches = catches
        bubble = ""
        pipState = .celebrating
        finished = true
    }

    /// Ask, listen, and resolve one planted mistake.
    private func teach(_ m: PlantedMistake, sentence s: PipSentence) async {
        var askedWhich = false
        var tries = 0
        while !Task.isCancelled, !skipRequested {
            if tapCaught == m.wordIndex { await caught(m, s, via: .tap); return }
            await say(tries == 0 && !askedWhich ? .didIGetItRight : (askedWhich ? .whichWord : .didIGetItRight))
            if tapCaught == m.wordIndex { await caught(m, s, via: .tap); return }
            let transcript = await listen(for: m)
            if tapCaught == m.wordIndex { await caught(m, s, via: .tap); return }
            if skipRequested { return }
            session.setDebug("pipReads.lastTranscript", transcript.text)
            let hit = detectCatch(transcript: transcript, mistake: m)
            session.setDebug("pipReads.match", hit ? "caught" : "not caught")
            if hit { await caught(m, s, via: .voice); return }
            if !askedWhich, isBareObjection(transcript: transcript, mistake: m) {
                askedWhich = true
                continue
            }
            tries += 1
            if tries >= 2 { break }
        }
        guard !Task.isCancelled, !skipRequested else { return }
        // Not caught: Pip notices and fixes it himself, then models it.
        pipState = .confused
        await say(.mixedOneUp)
        withAnimation(.spring(duration: 0.5)) { fixed.insert(m.wordIndex); flip = m.wordIndex }
        catches.append(CatchResult(wordIndex: m.wordIndex, caught: false, via: .missed))
        await readSentence(s, spoken: false)
    }

    private func listen(for m: PlantedMistake) async -> Transcript {
        guard !PipPlayer.shared.isSpeaking else { return .empty } // mic never opens while Pip talks
        stopRequested = false
        let l = Listeners.make()
        listener = l
        pipState = .listening
        bubble = ""
        await l.start()
        listening = true
        let start = Date()
        while !Task.isCancelled, !stopRequested, Date().timeIntervalSince(start) < listenSeconds {
            // Stop early as soon as the correct word is heard, so the catch feels instant.
            if detectCatch(transcript: l.partialText, mistake: m) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        let t = await l.stop()
        listening = false
        listener = nil
        pipState = .idle
        return t
    }

    private func caught(_ m: PlantedMistake, _ s: PipSentence, via: CatchVia) async {
        tapCaught = nil
        confetti += 1
        session.award(.mistakeCaught)
        catches.append(CatchResult(wordIndex: m.wordIndex, caught: true, via: via))
        session.catches = catches
        withAnimation(.spring(duration: 0.5)) { fixed.insert(m.wordIndex); flip = m.wordIndex }
        pipState = .celebrating
        bubble = m.reaction
        await PipPlayer.shared.speak(.expressive(m.reaction), onWord: nil)
        await readSentence(s, spoken: false)
    }

    // MARK: Debug

    private func registerDebug() {
        unregister = [
            session.registerDebugAction("Force catch") {
                if let m = plan?.mistakes.first(where: { !fixed.contains($0.wordIndex) && sentenceStarted($0.sentenceIndex) }) {
                    tapCaught = m.wordIndex
                    stopRequested = true
                }
            },
            session.registerDebugAction("Skip sentence") {
                skipRequested = true
                stopRequested = true
                PipPlayer.shared.stop()
            },
            session.registerDebugAction("Replay sentence") {
                if let plan, plan.sentences.indices.contains(current) {
                    Task { await readSentence(plan.sentences[current], spoken: !fixed.isEmpty ? false : true) }
                }
            },
            session.registerDebugAction("Queue catch transcript") {
                if let m = plan?.mistakes.first { MockListener.inject("no it says \(m.correct)") }
            },
        ]
    }
}
