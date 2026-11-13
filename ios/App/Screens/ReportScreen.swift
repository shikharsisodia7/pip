// End of a reading session: what the child did, for them and their grown-up.
// Only measured numbers appear; any tile without data is hidden.

import SwiftUI
import PipKit

struct ReportScreen: View {
    @Environment(Session.self) private var session
    @State private var showPractice = false
    @State private var startStars = 0
    @State private var saved = false

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
                    tile("star.fill", Palette.orangeOrb, "+\(max(0, session.rewards.stars - startStars))", "stars today")
                }

                if let p = session.diagnosis?.patterns.first {
                    GlassCard(colors: Palette.berryCard, radius: 26, padding: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sound to practice").font(.pip(14, .bold)).foregroundStyle(.white.opacity(0.75))
                            Text(p.kidLabel.prefix(1).uppercased() + p.kidLabel.dropFirst())
                                .font(.pip(22, .bold)).foregroundStyle(.white)
                            Text("For grown-ups: \(p.teacherLabel)")
                                .font(.pip(14, .semibold)).foregroundStyle(.white.opacity(0.8))
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
                        saveSummary()
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
        .onAppear {
            let earned = (session.pagesRead.values.map { RewardEvent.pageRead(correctWords: $0.metrics.wordsCorrect).stars }.reduce(0, +))
                + (session.catches.contains(where: \.caught) ? RewardEvent.mistakeCaught.stars : 0)
                + ((session.expression?.passed ?? false) ? RewardEvent.expressionLearned.stars : 0)
            startStars = max(0, session.rewards.stars - earned)
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

    private func saveSummary() {
        guard !saved, !session.pagesRead.isEmpty else { return }
        saved = true
        let t = session.sessionTotals
        ReadingLog.shared.add(SessionSummary(
            bookTitle: session.book.title,
            pages: session.pagesRead.count,
            wordsCorrect: t.correct,
            wordsTotal: t.total,
            wcpm: t.seconds > 5 ? (Double(t.correct) / (t.seconds / 60)).rounded() : nil,
            trickySound: session.diagnosis?.patterns.first?.kidLabel,
            trickyWords: session.trickyWords,
            starsEarned: max(0, session.rewards.stars - startStars)
        ))
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
