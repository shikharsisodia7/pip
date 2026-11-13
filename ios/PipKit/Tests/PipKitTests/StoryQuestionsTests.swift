import XCTest
@testable import PipKit

final class StoryQuestionsTests: XCTestCase {
    private let playtimePages = [
        "The little elephant's name was Golu. He was as round as a drum. The little rabbit was called Chhotu. He looked like a ball of cotton.",
        "They played together. One day, Golu said, \u{201C}Let's play a new game today.\u{201D}",
        "\u{201C}You sit down. I'll land on your back in one flying leap,\u{201D} said Chhotu. Golu sat down. Chhotu took a mighty leap.",
        "Thump! He landed on Golu's back. \u{201C}Wow!\u{201D} laughed Golu and said, \u{201C}My turn now. You sit down and I will leap on your back.\u{201D}",
        "\u{201C}You!\u{201D} \u{201C}Yes, me.\u{201D} \u{201C}How can you do that?\u{201D} asked Chhotu. \"Like this!\" Golu showed him. Thud... thud... thud... A shower of coconuts came down on Golu's head.",
        "He ran away on fat legs, scared. One small coconut fell on Chhotu. \u{2018}That's better,' thought Chhotu, \u{2018}Better a coconut than an elephant on my head!'",
    ]

    func testEveryDemoPageHasAnAnswerStatedOnThePage() {
        XCTAssertEqual(playtimeQuestions.count, playtimePages.count)
        for (i, text) in playtimePages.enumerated() {
            let q = storyQuestion(bookId: "playtime", pageIndex: i, pageText: text)
            XCTAssertEqual(q, playtimeQuestions[i], "page \(i) fell back to a generic question")
            let words = tokenize(text)
            let first = q.acceptedAnswers[0]
            XCTAssertTrue(first.allSatisfy { k in words.contains { fuzzyEqual($0, k) } }, "page \(i): \(first)")
        }
    }

    func testVerdicts() {
        let q = playtimeQuestions[0]
        XCTAssertEqual(judgeAnswer("Golu", for: q), .correct)
        XCTAssertEqual(judgeAnswer("it was the elephant", for: q), .correct)
        XCTAssertEqual(judgeAnswer("the rabbit", for: q), .tryAgain)
        XCTAssertEqual(judgeAnswer("", for: q), .noAnswer)
        XCTAssertEqual(judgeAnswer("um", for: q), .noAnswer)
        XCTAssertEqual(judgeAnswer("I don't know", for: q), .noAnswer)
        let game = playtimeQuestions[1]
        XCTAssertEqual(judgeAnswer("a new game", for: game), .correct)
        let twoWords = StoryQuestion(question: "q", acceptedAnswers: [["flying", "leap"]], hint: "h", answerLine: "a")
        XCTAssertEqual(judgeAnswer("a big leap", for: twoWords), .close)
    }

    func testFuzzyTolerance() {
        XCTAssertEqual(judgeAnswer("Chotu", for: playtimeQuestions[2]), .correct)
        XCTAssertEqual(judgeAnswer("coconut", for: playtimeQuestions[4]), .correct)
        XCTAssertEqual(judgeAnswer("he was scard", for: playtimeQuestions[5]), .correct)
    }

    func testFallbackWithAName() {
        let q = storyQuestion(bookId: "user-1234", pageIndex: 0, pageText: "The dog ran fast. Then Maya threw the ball far away.")
        XCTAssertEqual(q.question, "Who was on this page?")
        XCTAssertEqual(q.acceptedAnswers, [["maya"]])
        XCTAssertEqual(judgeAnswer("it was Maya", for: q), .correct)
    }

    func testFallbackWithoutNames() {
        let q = storyQuestion(bookId: "user-1234", pageIndex: 0, pageText: "The dog ran fast. It found a red ball in the garden.")
        XCTAssertEqual(q.question, "What happened on this page?")
        XCTAssertTrue(q.acceptedAnswers.isEmpty)
        XCTAssertEqual(judgeAnswer("the dog found a ball", for: q), .correct)
        XCTAssertEqual(judgeAnswer("ball", for: q), .close)
        XCTAssertEqual(judgeAnswer("I like pizza a lot", for: q), .tryAgain)
    }

    func testDemoQuestionFallsBackWhenPageTextChanged() {
        let q = storyQuestion(bookId: "playtime", pageIndex: 0, pageText: "A cat sat on a mat.")
        XCTAssertNotEqual(q, playtimeQuestions[0])
    }

    func testNoEmDashes() {
        for q in playtimeQuestions {
            for s in [q.question, q.hint, q.answerLine] { XCTAssertFalse(s.contains("\u{2014}"), s) }
        }
    }
}
