import XCTest
@testable import PipKit

final class LibraryTests: XCTestCase {
    func testFromTextSplitsIntoSentencePages() {
        let text = (1...12).map { "The frog jumped over log number \($0)." }.joined(separator: " ")
        let book = Book.fromText(title: "  Frogs ", text: text)
        XCTAssertEqual(book.title, "Frogs")
        XCTAssertTrue(book.isUserBook)
        XCTAssertGreaterThan(book.pages.count, 1)
        XCTAssertTrue(book.pages.allSatisfy { tokenize($0.text).count <= 32 })
        XCTAssertEqual(book.pages.map(\.index), Array(0..<book.pages.count))
        XCTAssertEqual(tokenize(book.pages.map(\.text).joined(separator: " ")), tokenize(text))
    }

    @MainActor func testSummaryCountsPagesReadThisSession() {
        let session = Session()
        session.startReading(BuiltInBooks.lionAndMouse)
        XCTAssertNil(session.summary())
        let page = BuiltInBooks.lionAndMouse.pages[0]
        let words = tokenizeDisplay(page.text).enumerated().map { i, t in
            TimedWord(text: t.norm, start: Double(i) * 0.4, end: Double(i) * 0.4 + 0.3)
        }
        let alignment = alignWords(expectedText: page.text, transcript: Transcript(text: "", words: words))
        session.pagesRead[0] = ReadResult(transcript: Transcript(text: "", words: words), alignment: alignment, metrics: computeMetrics(alignment))
        session.award(.pageRead(correctWords: alignment.words.count))
        let s = session.summary()
        XCTAssertEqual(s?.pages, 1)
        XCTAssertEqual(s?.wordsCorrect, s?.wordsTotal)
        XCTAssertEqual(s?.starsEarned, RewardEvent.pageRead(correctWords: alignment.words.count).stars)
    }

    @MainActor func testEveryPageIsPipThenChild() {
        let session = Session()
        let book = BuiltInBooks.lionAndMouse
        session.startReading(book)
        XCTAssertEqual(session.phase, .pipReads)
        XCTAssertEqual(session.pipPageIndex, 0)
        XCTAssertFalse(session.pipSlips(onPage: 0))
        XCTAssertTrue(session.pipSlips(onPage: 1))
        session.childReadsPage()
        XCTAssertEqual(session.phase, .read)
        XCTAssertEqual(session.readPageIndex, 0)
        session.nextPage()
        XCTAssertEqual(session.phase, .pipReads)
        XCTAssertEqual(session.pipPageIndex, 1)
        for _ in 1..<book.pages.count { session.childReadsPage(); session.nextPage() }
        XCTAssertEqual(session.phase, .report)
    }

    func testFromTextEmpty() {
        XCTAssertTrue(Book.fromText(title: "", text: "  \n ").pages.isEmpty)
    }

    func testLocalDiagnosisFindsMissedPattern() {
        let page = "He jumped and looked at the big red ball."
        let t = Transcript(text: "he jump and look at the big red ball", words: [
            "he", "jump", "and", "look", "at", "the", "big", "red", "ball",
        ].enumerated().map { TimedWord(text: $1, start: Double($0) * 0.4, end: Double($0) * 0.4 + 0.3) })
        let d = localDiagnosis(pageText: page, alignment: alignWords(expectedText: page, transcript: t))
        XCTAssertEqual(d.patterns.first?.id, "ed")
        XCTAssertEqual(d.patterns.first?.evidenceWords, ["jumped", "looked"])
        XCTAssertFalse(d.kidMessage.contains("\u{2014}"))
    }

    func testLocalPipPlanPlantsOneMistake() {
        let page = "They played together. One day, Golu said, \u{201C}Let's play a new game today.\u{201D}"
        let plan = localPipPlan(pageIndex: 1, pageText: page, patterns: [getPattern("ed")!.finding()])
        XCTAssertEqual(plan.sentences.count, 2)
        XCTAssertEqual(plan.mistakes.first?.correct, "played")
        XCTAssertEqual(plan.mistakes.first?.misread, "play")
        XCTAssertEqual(plan.sentences[0].spokenText, "They play together.")
    }

    func testBuiltInBooksAreReadable() {
        for book in [BuiltInBooks.lionAndMouse, BuiltInBooks.tortoiseAndHare] {
            XCTAssertGreaterThanOrEqual(book.pages.count, 5)
            XCTAssertFalse(book.pages.contains { $0.text.contains("\u{2014}") })
            XCTAssertFalse(localPipPlan(pageIndex: 1, pageText: book.pages[1].text, patterns: []).mistakes.isEmpty, book.title)
        }
    }
}
