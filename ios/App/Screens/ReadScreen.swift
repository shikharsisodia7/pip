// The child reads the book aloud, page by page. Every word lights up by how it
// went: green when read, warm yellow after a long pause, coral when skipped or
// misread. After each page Pip notices which sound was tricky, and when the
// child is ready, Pip takes a turn reading.

import SwiftUI
import PipKit

struct ReadScreen: View {
    @Environment(Session.self) private var session
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var listener: (any Listening)?
    @State private var prosody = ProsodyRecorder()
    @State private var finalMarks: [WordMark] = []
    @State private var finished = false
    @State private var thinking = false
    @State private var message: String?
    @State private var error: String?
    @State private var confetti = 0

    private var book: Book { session.book }
    private var index: Int { session.readPageIndex }
    private var page: BookPage? { session.readPage }
    private var isLast: Bool { index >= book.pages.count - 1 }

    private var isListening: Bool {
        guard let l = listener else { return false }
        return l.status == .listening || l.status == .connecting
    }

    private var marks: [WordMark] {
        guard let page else { return [] }
        if let l = listener, isListening {
            return liveMarks(expectedText: page.text, transcript: l.liveTranscript)
        }
        if finalMarks.isEmpty, let done = session.pagesRead[index] {
            return PipKit.marks(for: done.alignment)
        }
        return finalMarks
    }

    var body: some View {
        VStack(spacing: 14) {
            topBar
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if let page {
                            sceneCard(page)
                            storyCard(page)
                        }
                        if let error {
                            Text(error).font(.pip(15, .semibold)).foregroundStyle(Palette.sun).multilineTextAlignment(.center)
                        }
                        if finished { resultCard.id("result") }
                    }
                    .padding(.bottom, 12)
                }
                .task(id: "\(finished)\(thinking)") {
                    guard finished else { return }
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.spring(duration: 0.5)) { proxy.scrollTo("result", anchor: .bottom) }
                }
            }
            controls
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            registerDebug()
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "PipAutoListen") { toggle() }
            if UserDefaults.standard.bool(forKey: "PipSampleRead") { sampleReading() }
            #endif
        }
        .overlay {
            if confetti > 0 { Celebration().id(confetti).allowsHitTesting(false) }
        }
        .onChange(of: index) { resetPage() }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack(spacing: 12) {
            OrbButton(systemImage: "xmark", colors: Palette.blueOrb, size: 44) {
                Task { await stopListening(save: false) }
                session.reset()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(book.title).font(.pip(15, .bold)).foregroundStyle(.white).lineLimit(1)
                TrackBar(value: Double(index + 1) / Double(max(1, book.pages.count)))
            }
            Text("\(index + 1)/\(book.pages.count)")
                .font(.pip(15, .bold))
                .foregroundStyle(Palette.textSoft)
                .monospacedDigit()
            Label("\(session.rewards.stars)", systemImage: "star.fill")
                .font(.pip(15, .bold))
                .foregroundStyle(Palette.sun)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(Palette.glass))
                .contentTransition(.numericText())
        }
    }

    private func sceneCard(_ page: BookPage) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(hexString: page.scene.bg) ?? Palette.paper)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 2))
            Text(page.scene.emoji)
                .font(.system(size: finished ? 40 : (hSize == .compact ? 64 : 80)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            PipView(state: pipState, size: finished ? 70 : 86)
                .padding(.trailing, 4)
                .padding(.bottom, -10)
        }
        // After a page the scene steps back so the result has room.
        .frame(height: finished ? 100 : (hSize == .compact ? 170 : 200))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
    }

    private var pipState: PipState {
        if thinking { return .thinking }
        if isListening { return .listening }
        if finished { return .celebrating }
        return .idle
    }

    private func storyCard(_ page: BookPage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ReadingText(text: page.text, marks: marks, fontSize: hSize == .compact ? 27 : 32)
            ReadingLegend()
            if !book.isUserBook { StoryCredit(book: book, onPaper: true) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Palette.paper))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
    }

    private var resultCard: some View {
        let result = session.pagesRead[index]
        return GlassCard(colors: Palette.grapeCard, radius: 26, padding: 18) {
            HStack(alignment: .top, spacing: 14) {
                Orb(systemImage: thinking ? "ellipsis" : "sparkles", colors: Palette.orangeOrb, size: 46)
                VStack(alignment: .leading, spacing: 6) {
                    if let r = result {
                        Text("You read \(r.metrics.wordsCorrect) of \(r.metrics.wordsTotal) words!")
                            .font(.pip(19, .bold)).foregroundStyle(.white)
                    }
                    Text(thinking ? "Pip is thinking about your reading…" : (message ?? "Great reading!"))
                        .font(.pip(16, .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    if let p = session.diagnosis?.patterns.first, !p.evidenceWords.isEmpty, !thinking {
                        HStack(spacing: 8) {
                            ForEach(p.evidenceWords.prefix(3), id: \.self) { w in
                                Text(w).font(.pip(15, .bold)).foregroundStyle(Palette.ink)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(WordMark.missed.fill))
                            }
                        }
                    }
                }
            }
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    @ViewBuilder private var controls: some View {
        if finished {
            HStack(spacing: 12) {
                BigButton("Again", variant: .secondary, systemImage: "arrow.counterclockwise") { resetPage() }
                if isLast {
                    BigButton("Pip's turn!", systemImage: "arrow.right") { session.startPipsTurn() }
                } else {
                    BigButton("Next page", systemImage: "arrow.right") { session.readPageIndex += 1 }
                }
            }
            if !isLast {
                Button("I'm done, Pip's turn!") { session.startPipsTurn() }
                    .font(.pip(16, .bold))
                    .foregroundStyle(Palette.accent)
            }
        } else {
            VStack(spacing: 8) {
                MicButton(state: isListening ? .listening : .idle,
                          label: isListening ? "Tap when you're done" : "Tap and read to Pip", size: 92) { toggle() }
                if isListening {
                    Meter(value: Double(MicHub.shared.level), tone: .accent, height: 8).frame(width: 160)
                }
            }
        }
    }

    // MARK: Actions

    private func toggle() {
        if isListening {
            Task { await stopListening(save: true) }
        } else {
            error = nil
            let l = Listeners.make()
            listener = l
            finalMarks = []
            Task {
                await l.start()
                if l.status == .error {
                    error = l.errorMessage ?? "Pip could not hear you. Try again?"
                    listener = nil
                    return
                }
                prosody.start()
                // A blocked microphone delivers exact zeros. Say so instead of
                // letting the child read to a Pip who cannot hear.
                try? await Task.sleep(for: .seconds(3))
                if listener === l, isListening, !MicHub.shared.heardSound {
                    error = "Pip can't hear the microphone. Check that the mic is turned on."
                }
            }
        }
    }

    private func stopListening(save: Bool) async {
        guard let l = listener else { return }
        let stats = prosody.stop()
        let transcript = await l.stop()
        listener = nil
        guard save else { return }
        guard !transcript.words.isEmpty else {
            error = "Pip didn't hear any words. Try reading a little louder?"
            return
        }
        finish(transcript, prosody: stats)
    }

    private func finish(_ transcript: Transcript, prosody stats: ProsodyStats?) {
        guard let page else { return }
        let alignment = alignWords(expectedText: page.text, transcript: transcript)
        let metrics = computeMetrics(alignment)
        let result = ReadResult(transcript: transcript, alignment: alignment, metrics: metrics)
        session.read = result
        session.pagesRead[index] = result
        if let stats, stats.voicedFrames > 0 { session.baselineProsody = stats }
        Library.shared.markRead(book.id, page: index)
        finalMarks = PipKit.marks(for: alignment)
        withAnimation(.spring) { finished = true }
        confetti += 1
        session.award(.pageRead(correctWords: metrics.wordsCorrect))

        thinking = true
        message = nil
        Task {
            let d = (try? await API.current.diagnose(pageText: page.text, alignment: alignment, metrics: metrics))
                ?? localDiagnosis(pageText: page.text, alignment: alignment)
            session.diagnosis = d
            message = d.kidMessage
            thinking = false
        }
    }

    private func resetPage() {
        finished = false
        finalMarks = []
        message = nil
        error = nil
        thinking = false
    }

    private func registerDebug() {
        session.registerDebugAction("Read this page with a sample reading") { sampleReading() }
    }

    private func sampleReading() {
        guard let page else { return }
        finish(SampleReading.transcript(for: page.text), prosody: nil)
    }
}

/// A made-up reading with one skipped word, one misread word and one long
/// pause, for the debug panel and screenshots. Never shown as a real result.
enum SampleReading {
    static func transcript(for text: String) -> Transcript {
        let words = tokenizeDisplay(text).enumerated().compactMap { i, t -> TimedWord? in
            if i == 3 { return nil }
            return TimedWord(text: i == 6 ? "ball" : t.norm, start: Double(i) * 0.45 + (i > 9 ? 1.5 : 0), end: Double(i) * 0.45 + 0.35 + (i > 9 ? 1.5 : 0))
        }
        return Transcript(text: words.map(\.text).joined(separator: " "), words: words)
    }

    @MainActor static func fill(_ session: Session, page index: Int) {
        guard let page = session.book.pages[safe: index] else { return }
        let alignment = alignWords(expectedText: page.text, transcript: transcript(for: page.text))
        let result = ReadResult(transcript: transcript(for: page.text), alignment: alignment, metrics: computeMetrics(alignment))
        session.read = result
        session.pagesRead[index] = result
        session.diagnosis = localDiagnosis(pageText: page.text, alignment: alignment)
    }
}
