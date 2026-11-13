import XCTest
@testable import PipKit

final class TextTests: XCTestCase {
    func testNormalize() {
        XCTAssertEqual(normalizeToken("Drum."), "drum")
        XCTAssertEqual(normalizeToken("\u{201C}Let's"), "let's")
        XCTAssertEqual(normalizeToken("elephant\u{2019}s"), "elephant's")
        XCTAssertEqual(normalizeToken("3"), "three")
        XCTAssertEqual(normalizeToken("--"), "")
    }

    func testTokenizeDropsPunctuationOnlyTokens() {
        let t = tokenizeDisplay("Golu said, \u{201C}Let's play\u{2014}now!\u{201D} \u{2014} ok")
        XCTAssertEqual(t.map(\.norm), ["golu", "said", "let's", "play", "now", "ok"])
        XCTAssertEqual(t[1].display, "said,")
    }

    func testFuzzy() {
        XCTAssertTrue(fuzzyEqual("Elephant", "elephent"))
        XCTAssertFalse(fuzzyEqual("cat", "cot"))
        XCTAssertTrue(fuzzyEqual("lets", "let's"))
        XCTAssertEqual(editDistance("kitten", "sitting"), 3)
    }
}

final class PatternTests: XCTestCase {
    func testPatterns() {
        XCTAssertTrue(getPattern("ed")!.test("looked"))
        XCTAssertFalse(getPattern("ed")!.test("need"))
        XCTAssertTrue(getPattern("silent-e")!.test("smile"))
        XCTAssertFalse(getPattern("silent-e")!.test("have"))
        XCTAssertEqual(patternsForWord("thought").first?.id, "ough")
        XCTAssertEqual(Patterns.all.count, 19)
    }

    func testWordsWithPattern() {
        let hits = wordsWithPattern("He looked like a ball of cotton.", "ed")
        XCTAssertEqual(hits.map(\.index), [1])
        XCTAssertEqual(hits.first?.display, "looked")
    }
}

final class LiveMarksTests: XCTestCase {
    let page = "The cat sat on the mat."

    func testPartialKeepsRestPending() {
        let t = Transcript(text: "the cat", words: [
            TimedWord(text: "the", start: 0, end: 0.3),
            TimedWord(text: "cat", start: 0.4, end: 0.7),
        ])
        XCTAssertEqual(liveMarks(expectedText: page, transcript: t),
                       [.correct, .correct, .current, .pending, .pending, .pending])
    }

    func testHesitationAndMiss() {
        let t = Transcript(text: "the cot sat", words: [
            TimedWord(text: "the", start: 0, end: 0.3),
            TimedWord(text: "cot", start: 0.4, end: 0.7),
            TimedWord(text: "sat", start: 2.0, end: 2.3),
        ])
        let m = liveMarks(expectedText: page, transcript: t)
        XCTAssertEqual(Array(m.prefix(4)), [.correct, .missed, .hesitant, .current])
        XCTAssertEqual(liveMarks(expectedText: page, transcript: t, final: true).last, .missed)
    }

    func testEmpty() {
        XCTAssertEqual(liveMarks(expectedText: page, transcript: .empty).first, .current)
    }
}

final class RewardTests: XCTestCase {
    func testStagesClimbThroughDemo() {
        var r = RewardState()
        XCTAssertEqual(r.stage, 1)
        r.apply(.pageRead(correctWords: 24))
        XCTAssertEqual(r.stage, 2)
        r.apply(.mistakeCaught)
        XCTAssertEqual(r.stage, 3)
        r.apply(.expressionLearned)
        XCTAssertEqual(r.stage, 4)
        XCTAssertEqual(r.stickers, ["glow", "star", "crown"])
        XCTAssertNil(r.starsToNextStage)
    }
}

@MainActor
final class SessionTests: XCTestCase {
    func testTwoMinutePathSkipsProbes() {
        XCTAssertEqual(nextPhase(after: .intro, demoPath: .twoMin), .read)
        XCTAssertEqual(nextPhase(after: .expression, demoPath: .twoMin), .report)
        XCTAssertEqual(nextPhase(after: .intro, demoPath: .full), .probePre)
        XCTAssertEqual(nextPhase(after: .report, demoPath: .full), .report)
    }

    func testModelsDecodeServerJSON() throws {
        let json = ##"{"index":1,"text":"Hi.","scene":{"emoji":"🐘","bg":"#fff"},"emotionLine":{"text":"Hi.","speaker":"Golu","emotion":"excited"}}"##
        let page = try JSONDecoder().decode(BookPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.emotionLine?.emotion, .excited)
        XCTAssertNil(page.imageUrl)
    }

    func testScribeDecode() {
        let msg = #"{"message_type":"committed_transcript_with_timestamps","text":"hi there","words":[{"text":"hi","start":0.1,"end":0.3,"type":"word"},{"text":" ","start":0.3,"end":0.35,"type":"spacing"},{"text":"there","start":0.4,"end":0.7,"type":"word"}]}"#
        guard case .committed(let text, let words) = ScribeCodec.decode(msg) else { return XCTFail() }
        XCTAssertEqual(text, "hi there")
        XCTAssertEqual(words.map(\.text), ["hi", "there"])
    }
}
