// End of a reading session: what the child did, for them and their grown-up.
// Only measured numbers appear; any tile without data is hidden.

import SwiftUI
import PipKit

struct ReportScreen: View {
    @Environment(Session.self) private var session
    @State private var showPractice = false
    /// The latest session saved before this one. Read on appear: this session is
    /// only added to the log when the child leaves the report.
    @State private var previous: SessionSummary?

    var body: some View {
        let totals = session.sessionTotals
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    PipView(state: .celebrating, size: 130)
                    Text("What Pip learned from today's reading")
                        .font(.pip(26, .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(session.book.title)
                        .font(.pip(16, .semibold))
                        .foregroundStyle(Palette.textSoft)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    if totals.total > 0 {
                        tile("text.word.spacing", Palette.mintOrb, "\(totals.correct)/\(totals.total)", "words read right")
                        tile("target", Palette.blueOrb, "\(Int((Double(totals.correct) / Double(totals.total) * 100).rounded()))%", "accuracy")
                    }
                    if totals.seconds > 5 {
                        tile("speedometer", Palette.purpleOrb, "\(Int((Double(totals.correct) / (totals.seconds / 60)).rounded()))", "words a minute")
                    }
                    if !session.catches.isEmpty {
                        tile("hand.raised.fill", Palette.pinkOrb, "\(session.catches.filter(\.caught).count)/\(session.catches.count)", "Pip mistakes caught")
                    }
                    if let e = session.expression {
                        tile("theatermasks.fill", Palette.orangeOrb, String(format: "%.1fx", e.score), "more expression than your first read")
                    }
                    if understanding.asked > 0 {
                        tile("bubble.left.and.text.bubble.right.fill", Palette.blueOrb, "\(understanding.correct)/\(understanding.asked)", "story questions")
                    }
                    tile("star.fill", Palette.orangeOrb, "+\(max(0, session.rewards.stars - session.startStars))", "stars today")
                }

                if let prev = previous, let today = session.summary() {
                    sinceLastTime(today: today, previous: prev)
                }

                if let p = session.diagnosis?.patterns.first {
                    GlassCard(colors: Palette.berryCard, radius: 26, padding: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sound to practice").font(.pip(14, .bold)).foregroundStyle(.white.opacity(0.75))
                            Text(p.kidLabel.prefix(1).uppercased() + p.kidLabel.dropFirst())
                                .font(.pip(22, .bold)).foregroundStyle(.white)
                            Text("For grown-ups: \(p.teacherLabel)")
                                .font(.pip(14, .semibold)).foregroundStyle(.white.opacity(0.8))
                            if understanding.asked > 0 {
                                Text("Understanding: answered \(understanding.correct) of \(understanding.asked) story questions.")
                                    .font(.pip(14, .semibold)).foregroundStyle(.white.opacity(0.8))
                            }
                            let words = session.trickyWords
                            if !words.isEmpty {
                                Text("Tricky today: " + words.prefix(6).joined(separator: ", "))
                                    .font(.pip(15, .semibold)).foregroundStyle(Palette.sun)
                            }
                        }
                    }
                }

                if let last = session.pagesRead.keys.max(), let r = session.pagesRead[last], let page = session.book.pages[safe: last] {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your last page").font(.pip(15, .bold)).foregroundStyle(Palette.ink.opacity(0.6))
                        ReadingText(text: page.text, marks: marks(for: r.alignment), fontSize: 22)
                        ReadingLegend()
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Palette.paper))
                }

                if session.pagesRead.isEmpty {
                    Text("Read a page to Pip to see your reading here.")
                        .font(.pip(16, .semibold)).foregroundStyle(Palette.textSoft)
                }

                VStack(spacing: 12) {
                    if session.diagnosis != nil {
                        BigButton("Pip's Practice Book", variant: .secondary, systemImage: "book.closed.fill") { showPractice = true }
                    }
                    BigButton("Back home", systemImage: "house.fill") {
                        ComprehensionLog.shared.clear()
                        session.reset()
                    }
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showPractice) { PracticeScreen().environment(session) }
        .onAppear { if previous == nil { previous = ReadingLog.shared.sessions.first } }
    }

    /// Story questions answered this session (from ComprehensionLog).
    private var understanding: (correct: Int, asked: Int) { ComprehensionLog.shared.totals(bookId: session.book.id) }

    private func accuracy(_ s: SessionSummary) -> Int? {
        s.wordsTotal > 0 ? Int((Double(s.wordsCorrect) / Double(s.wordsTotal) * 100).rounded()) : nil
    }

    /// Today next to the previous session. Only numbers measured in both appear.
    @ViewBuilder
    private func sinceLastTime(today: SessionSummary, previous prev: SessionSummary) -> some View {
        let wcpm: (Int, Int)? = {
            guard let a = today.wcpm, let b = prev.wcpm else { return nil }
            return (Int(a.rounded()), Int(b.rounded()))
        }()
        let acc: (Int, Int)? = {
            guard let a = accuracy(today), let b = accuracy(prev) else { return nil }
            return (a, b)
        }()
        let soundChanged = today.trickySound != nil && prev.trickySound != nil && today.trickySound != prev.trickySound
        if wcpm != nil || acc != nil || soundChanged {
            let faster = wcpm.map { $0.0 > $0.1 } ?? false
            let moreRight = acc.map { $0.0 > $0.1 } ?? false
            GlassCard(radius: 26, padding: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Since last time").font(.pip(14, .bold)).foregroundStyle(.white.opacity(0.75))
                    if let w = wcpm { compareRow("words a minute", today: "\(w.0)", before: "\(w.1)", up: w.0 > w.1) }
                    if let a = acc { compareRow("accuracy", today: "\(a.0)%", before: "\(a.1)%", up: a.0 > a.1) }
                    if wcpm != nil || acc != nil {
                        Text(faster ? "You read faster than last time!"
                             : moreRight ? "You read more words right than last time!"
                             : "Every reading makes you stronger.")
                            .font(.pip(17, .bold)).foregroundStyle(Palette.sun)
                    }
                    if soundChanged, let before = prev.trickySound, let now = today.trickySound {
                        Text("Last time: \(before). Today: \(now).")
                            .font(.pip(14, .semibold)).foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func compareRow(_ label: String, today: String, before: String, up: Bool) -> some View {
        HStack(spacing: 10) {
            Text(today).font(.pip(24, .bold)).foregroundStyle(.white)
            if up {
                Image(systemName: "arrow.up").font(.pip(16, .bold)).foregroundStyle(Palette.mint)
            }
            Text(label).font(.pip(15, .semibold)).foregroundStyle(Palette.textSoft)
            Spacer()
            Text("last time \(before)").font(.pip(14, .semibold)).foregroundStyle(.white.opacity(0.7))
        }
    }

    private func tile(_ icon: String, _ colors: [Color], _ value: String, _ label: String) -> some View {
        GlassCard(radius: 24, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Orb(systemImage: icon, colors: colors, size: 38)
                Text(value).font(.pip(26, .bold)).foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
                Text(label).font(.pip(13, .semibold)).foregroundStyle(Palette.textSoft).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
