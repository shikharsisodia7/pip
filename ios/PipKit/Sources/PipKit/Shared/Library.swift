// The child's bookshelf: built-in stories plus any page a grown-up adds by
// typing, pasting or scanning a real book. Saved on the device.

import Foundation
import Observation

public extension Book {
    var wordCount: Int { pages.reduce(0) { $0 + tokenize($1.text).count } }

    /// Rough reading time for an early reader (about 40 words a minute).
    var minutes: Int { max(1, Int((Double(wordCount) / 40).rounded())) }

    /// 1 to 5 from the hardest phonics pattern in the book.
    var level: Int { hardestPatternIn(pages.map(\.text).joined(separator: " "))?.difficulty ?? 1 }

    var isUserBook: Bool { id.hasPrefix("user-") }

    /// Splits pasted or scanned text into pages of whole sentences, about 30 words each.
    static func fromText(title: String, text: String) -> Book {
        let clean = text.replacingOccurrences(of: "\r", with: "")
        let sentences = clean
            .components(separatedBy: "\n\n")
            .flatMap { para -> [String] in
                let flat = para.replacingOccurrences(of: "\n", with: " ")
                guard let re = try? NSRegularExpression(pattern: "[^.!?]+[.!?]+[\"'\u{201D}\u{2019}]*|[^.!?]+$") else { return [flat] }
                return re.matches(in: flat, range: NSRange(flat.startIndex..., in: flat))
                    .compactMap { Range($0.range, in: flat).map { String(flat[$0]).trimmingCharacters(in: .whitespaces) } }
            }
            .filter { !tokenize($0).isEmpty }
        var pages: [String] = []
        var current = ""
        for s in sentences {
            if !current.isEmpty, tokenize(current).count + tokenize(s).count > 32 {
                pages.append(current)
                current = s
            } else {
                current = current.isEmpty ? s : current + " " + s
            }
        }
        if !current.isEmpty { pages.append(current) }
        let scenes = [("📖", "#e6ebff"), ("✨", "#fff2c9"), ("🌈", "#e3f7ee"), ("🌙", "#efe6ff"), ("🌼", "#ffe8ef")]
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return Book(
            id: "user-\(UUID().uuidString.prefix(8))",
            title: trimmedTitle.isEmpty ? "My book" : trimmedTitle,
            author: "Added on this device", illustrator: "", publisher: "", license: "", sourceUrl: "",
            pages: pages.enumerated().map { i, t in
                let s = scenes[i % scenes.count]
                return BookPage(index: i, text: t, scene: PageScene(emoji: s.0, bg: s.1))
            }
        )
    }
}

@Observable @MainActor
public final class Library {
    public static let shared = Library()

    /// Built-in books, then the ones added on this device (newest first).
    public private(set) var books: [Book] = BuiltInBooks.all
    /// Pages finished per book id.
    public private(set) var pagesDone: [String: Set<Int>] = [:]

    private let userKey = "PipUserBooks", progressKey = "PipPagesDone"
    private var userBooks: [Book] = []

    public init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: userKey), let b = try? JSONDecoder().decode([Book].self, from: data) { userBooks = b }
        if let data = d.data(forKey: progressKey), let p = try? JSONDecoder().decode([String: Set<Int>].self, from: data) { pagesDone = p }
        rebuild()
    }

    /// Replaces the bundled Playtime with the server's copy when it loads.
    public func setFeatured(_ book: Book) {
        BuiltInBooks.featured = book
        rebuild()
    }

    public func add(_ book: Book) {
        userBooks.insert(book, at: 0)
        save()
    }

    public func remove(_ id: String) {
        userBooks.removeAll { $0.id == id }
        pagesDone[id] = nil
        save()
    }

    public func markRead(_ bookId: String, page: Int) {
        pagesDone[bookId, default: []].insert(page)
        save()
    }

    public func progress(_ book: Book) -> Double {
        guard !book.pages.isEmpty else { return 0 }
        return Double(pagesDone[book.id]?.count ?? 0) / Double(book.pages.count)
    }

    /// The first page not read yet, or 0 when the book is finished.
    public func nextPage(_ book: Book) -> Int {
        let done = pagesDone[book.id] ?? []
        return book.pages.indices.first { !done.contains($0) } ?? 0
    }

    /// The book to suggest on the home screen: started but unfinished, else the first new one.
    public var continueBook: Book? {
        books.first { (0.01..<1).contains(progress($0)) } ?? books.first { progress($0) == 0 } ?? books.first
    }

    public var totalPagesRead: Int { pagesDone.values.reduce(0) { $0 + $1.count } }

    private func rebuild() { books = BuiltInBooks.all + userBooks }

    private func save() {
        rebuild()
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(userBooks) { d.set(data, forKey: userKey) }
        if let data = try? JSONEncoder().encode(pagesDone) { d.set(data, forKey: progressKey) }
    }
}

public enum BuiltInBooks {
    @MainActor static var featured: Book = .placeholder

    @MainActor static var all: [Book] { [featured, lionAndMouse, tortoiseAndHare] }

    private static func retold(_ id: String, _ title: String, _ pages: [BookPage]) -> Book {
        Book(id: id, title: title, author: "Aesop, retold for Pip", illustrator: "", publisher: "",
             license: "Public domain fable", sourceUrl: "", pages: pages)
    }

    static let lionAndMouse = retold("lion-and-mouse", "The Lion and the Mouse", [
        BookPage(index: 0, text: "A big lion was sleeping in the warm sun. A little mouse ran right over his nose.",
                 scene: PageScene(emoji: "🦁 💤 🐭", bg: "#fff2c9")),
        BookPage(index: 1, text: "The lion woke up and trapped the mouse under his paw. \u{201C}Please let me go!\u{201D} cried the mouse. \u{201C}One day I might help you.\u{201D}",
                 scene: PageScene(emoji: "🦁 🐾 🐭", bg: "#ffe8ef"),
                 emotionLine: EmotionLine(text: "Please let me go!", speaker: "the mouse", emotion: .scared)),
        BookPage(index: 2, text: "The lion laughed, but he lifted his paw. The mouse jumped down and raced away.",
                 scene: PageScene(emoji: "😄 🦁 🐭 💨", bg: "#e3f7ee")),
        BookPage(index: 3, text: "That night, the lion was caught in a hunter's net. He roared and roared, but he could not get out.",
                 scene: PageScene(emoji: "🌙 🕸️ 🦁", bg: "#efe6ff"),
                 emotionLine: EmotionLine(text: "He roared and roared!", speaker: "the lion", emotion: .shouting)),
        BookPage(index: 4, text: "The mouse heard the loud roar. She chewed the ropes until the net broke. \u{201C}You helped me, and now I helped you!\u{201D} she said.",
                 scene: PageScene(emoji: "🐭 🪢 🦁 💛", bg: "#e6ebff"),
                 emotionLine: EmotionLine(text: "You helped me, and now I helped you!", speaker: "the mouse", emotion: .happy)),
    ])

    static let tortoiseAndHare = retold("tortoise-and-hare", "The Tortoise and the Hare", [
        BookPage(index: 0, text: "The hare was very fast, and he liked to show off. \u{201C}Nobody can beat me!\u{201D} he shouted.",
                 scene: PageScene(emoji: "🐇 💨", bg: "#e3f7ee"),
                 emotionLine: EmotionLine(text: "Nobody can beat me!", speaker: "the hare", emotion: .shouting)),
        BookPage(index: 1, text: "The slow tortoise smiled. \u{201C}Let's have a race,\u{201D} she said. All the animals came to watch.",
                 scene: PageScene(emoji: "🐢 🏁 🐇", bg: "#fff2c9"),
                 emotionLine: EmotionLine(text: "Let's have a race!", speaker: "the tortoise", emotion: .excited)),
        BookPage(index: 2, text: "The hare jumped ahead. Soon he could not see the tortoise at all, so he lay down for a nap under a tree.",
                 scene: PageScene(emoji: "🌳 🐇 💤", bg: "#e6ebff")),
        BookPage(index: 3, text: "The tortoise kept walking, step by step. She passed the sleeping hare and did not stop.",
                 scene: PageScene(emoji: "🐢 👣 🌳", bg: "#ffe8ef")),
        BookPage(index: 4, text: "The hare woke up and ran as fast as he could. But the tortoise had already crossed the finish line!",
                 scene: PageScene(emoji: "🐢 🏆 🐇 😮", bg: "#efe6ff"),
                 emotionLine: EmotionLine(text: "But the tortoise had already won!", speaker: "the crowd", emotion: .excited)),
    ])
}

/// One finished reading session, kept for the Progress tab.
public struct SessionSummary: Codable, Sendable, Identifiable, Equatable {
    public var id = UUID()
    public var date = Date()
    public var bookTitle: String
    public var pages: Int
    public var wordsCorrect: Int
    public var wordsTotal: Int
    public var wcpm: Double?
    public var trickySound: String?
    public var trickyWords: [String]
    public var starsEarned: Int

    public init(bookTitle: String, pages: Int, wordsCorrect: Int, wordsTotal: Int, wcpm: Double?,
                trickySound: String?, trickyWords: [String], starsEarned: Int) {
        self.bookTitle = bookTitle; self.pages = pages; self.wordsCorrect = wordsCorrect; self.wordsTotal = wordsTotal
        self.wcpm = wcpm; self.trickySound = trickySound; self.trickyWords = trickyWords; self.starsEarned = starsEarned
    }
}

@Observable @MainActor
public final class ReadingLog {
    public static let shared = ReadingLog()
    public private(set) var sessions: [SessionSummary] = []
    private let key = "PipReadingLog"

    public init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode([SessionSummary].self, from: data) { sessions = s }
    }

    public func add(_ s: SessionSummary) {
        sessions.insert(s, at: 0)
        sessions = Array(sessions.prefix(30))
        if let data = try? JSONEncoder().encode(sessions) { UserDefaults.standard.set(data, forKey: key) }
    }
}

public extension Session {
    /// Totals across every page read this session.
    var sessionTotals: (correct: Int, total: Int, seconds: Double) {
        pagesRead.values.reduce((0, 0, 0)) { acc, r in
            (acc.0 + r.metrics.wordsCorrect, acc.1 + r.metrics.wordsTotal, acc.2 + r.metrics.durationSec)
        }
    }

    /// This session for the reading log, or nil when no page was read.
    func summary() -> SessionSummary? {
        guard !pagesRead.isEmpty else { return nil }
        let t = sessionTotals
        return SessionSummary(
            bookTitle: book.title,
            pages: pagesRead.count,
            wordsCorrect: t.correct,
            wordsTotal: t.total,
            wcpm: t.seconds > 5 ? (Double(t.correct) / (t.seconds / 60)).rounded() : nil,
            trickySound: diagnosis?.patterns.first?.kidLabel,
            trickyWords: trickyWords,
            starsEarned: max(0, rewards.stars - startStars)
        )
    }

    /// Words the child skipped or misread this session, in page order, without repeats.
    var trickyWords: [String] {
        var seen = Set<String>()
        return pagesRead.keys.sorted().flatMap { i in
            pagesRead[i]!.alignment.words.filter { $0.status == .substitution || $0.status == .omission }.map(\.expected)
        }.filter { seen.insert($0).inserted }
    }
}
