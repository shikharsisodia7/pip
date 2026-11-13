// Pip's Practice Book: short sentences full of the sound the child found tricky,
// with that sound's letters picked out in color.

import SwiftUI
import PipKit

struct PracticeScreen: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var book: PracticeBook?

    private var pattern: PatternFinding {
        session.diagnosis?.patterns.first ?? (getPattern("ed") ?? Patterns.all[0]).finding()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        PipView(state: .idle, size: 80)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book?.title ?? "Pip's Practice Book").font(.pip(24, .bold)).foregroundStyle(.white)
                            Text("Practicing \(pattern.kidLabel)").font(.pip(15, .semibold)).foregroundStyle(Palette.sun)
                        }
                    }
                    if let book {
                        ForEach(Array(book.sentences.enumerated()), id: \.offset) { i, s in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(i + 1)").font(.pip(16, .bold)).foregroundStyle(.white)
                                    .frame(width: 30, height: 30).background(Circle().fill(Palette.purple))
                                highlighted(s).font(.pip(24, .semibold))
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.paper))
                        }
                        ShareLink(item: ([book.title] + book.sentences).joined(separator: "\n")) {
                            Label("Share with a grown-up", systemImage: "square.and.arrow.up")
                                .font(.pip(17, .bold))
                        }
                        .tint(Palette.accent)
                    } else {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(40)
                    }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(PipBackdrop().ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .task {
            book = try? await API.current.practiceBook(pattern: pattern)
            session.practiceBook = book
        }
    }

    /// Bolds and colors the words that contain the target sound.
    private func highlighted(_ sentence: String) -> Text {
        let hits = Set(wordsWithPattern(sentence, pattern.id).map(\.index))
        return tokenizeDisplay(sentence).enumerated().reduce(Text("")) { acc, item in
            let (i, t) = item
            let word = hits.contains(i)
                ? Text(t.display).foregroundColor(Color(hex: 0xC2410C)).bold().underline()
                : Text(t.display).foregroundColor(Palette.ink)
            return i == 0 ? acc + word : acc + Text(" ") + word
        }
    }
}
