// Story question results for the current reading session, keyed by page index.
// Session lives in Shared and cannot change, so the screens that end a session
// (close and Back home) clear this store, and a new book starts it fresh.

import Foundation
import Observation
import PipKit

@Observable @MainActor
final class ComprehensionLog {
    static let shared = ComprehensionLog()

    struct Entry: Equatable {
        var verdict: AnswerVerdict
        var tries: Int
        var correct: Bool { verdict == .correct }
    }

    private(set) var bookId: String?
    private(set) var entries: [Int: Entry] = [:]
    /// Debug panel hook: the next answer the open question card should hear.
    var injectedAnswer: String?

    func record(page: Int, bookId: String, verdict: AnswerVerdict, tries: Int) {
        if self.bookId != bookId { entries = [:]; self.bookId = bookId }
        entries[page] = Entry(verdict: verdict, tries: tries)
    }

    func entry(page: Int, bookId: String) -> Entry? {
        self.bookId == bookId ? entries[page] : nil
    }

    /// (correct, asked) for a book, counting first and second try answers as correct.
    func totals(bookId: String) -> (correct: Int, asked: Int) {
        guard self.bookId == bookId else { return (0, 0) }
        return (entries.values.filter(\.correct).count, entries.count)
    }

    func clear() {
        entries = [:]
        bookId = nil
        injectedAnswer = nil
    }
}
