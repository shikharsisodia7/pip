// First working version of the Read screen: the child reads page 0 aloud and
// every word lights up by how it went. The full screen (diagnosis, result card)
// builds on this.

import SwiftUI
import PipKit

struct ReadScreen: View {
    @Environment(Session.self) private var session
    @State private var listener: (any Listening)?
    @State private var finalMarks: [WordMark] = []
    @State private var finished = false

    private var page: BookPage? { session.readPage }

    private var isListening: Bool {
        guard let l = listener else { return false }
        return l.status == .listening || l.status == .connecting
    }

    private var currentMarks: [WordMark] {
        guard let page else { return [] }
        if let l = listener, isListening {
            return liveMarks(expectedText: page.text, transcript: l.liveTranscript)
        }
        return finalMarks
    }

    var body: some View {
        if let page {
            HStack(spacing: 24) {
                scene(page)
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        ReadingText(text: page.text, marks: currentMarks, fontSize: 30)
                        ReadingLegend()
                        StoryCredit(book: session.book, onPaper: true)
                    }
                    .padding(24)
                    .background(Palette.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                    HStack(spacing: 20) {
                        MicButton(state: isListening ? .listening : .idle,
                                  label: isListening ? "Tap when you're done" : "Tap and read to Pip",
                                  size: 90) { toggle() }
                        if isListening {
                            Meter(value: Double(MicHub.shared.level), tone: .accent, height: 10).frame(width: 140)
                        }
                        Spacer()
                        if finished {
                            BigButton("Let Pip try", systemImage: "arrow.right") { session.advance() }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear(perform: registerDebug)
        }
    }

    private func scene(_ page: BookPage) -> some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(hexString: page.scene.bg) ?? Palette.surface)
            Text(page.scene.emoji)
                .font(.system(size: 90))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            PipView(state: isListening ? .listening : (finished ? .celebrating : .idle), size: 80)
                .padding(8)
        }
        .frame(width: 260)
    }

    private func toggle() {
        if let l = listener, isListening {
            Task { finish(await l.stop()) }
        } else {
            let l = Listeners.make()
            listener = l
            finished = false
            finalMarks = []
            Task { await l.start() }
        }
    }

    private func finish(_ transcript: Transcript) {
        guard let page else { return }
        let alignment = alignWords(expectedText: page.text, transcript: transcript)
        let metrics = computeMetrics(alignment)
        session.read = ReadResult(transcript: transcript, alignment: alignment, metrics: metrics)
        finalMarks = marks(for: alignment)
        listener = nil
        finished = true
        session.award(.pageRead(correctWords: metrics.wordsCorrect))
    }

    private func registerDebug() {
        session.registerDebugAction("Fill Read with demo transcript") {
            let t: Transcript = (try? API.fixture("page1-demo")) ?? .empty
            finish(t)
        }
    }
}
