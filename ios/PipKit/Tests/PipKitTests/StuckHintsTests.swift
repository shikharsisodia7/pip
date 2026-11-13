import XCTest
@testable import PipKit

final class StuckHintsTests: XCTestCase {
    func testChunksKeepLetterTeamsAndEdEnding() {
        XCTAssertEqual(readingChunks("looked"), ["l", "oo", "k", "ed"])
        XCTAssertEqual(readingChunks("thought"), ["th", "ough", "t"])
        XCTAssertEqual(readingChunks("night"), ["n", "igh", "t"])
        XCTAssertEqual(readingChunks("Round."), ["r", "ou", "n", "d"])
        XCTAssertEqual(readingChunks("bed"), ["b", "e", "d"])
        XCTAssertEqual(readingChunks(""), [])
    }

    func testChunksRebuildTheWord() {
        for word in ["elephant", "cotton", "played", "together", "drum", "chhotu", "let's"] {
            XCTAssertEqual(readingChunks(word).joined(), normalizeToken(word), word)
        }
    }

    func testHintMarksTheTrickyChunk() {
        let h = stuckHint(for: "looked")
        XCTAssertEqual(h.chunks, ["l", "oo", "k", "ed"])
        XCTAssertEqual(h.trickyIndex, 3)
        XCTAssertEqual(h.patternLabel, "words ending in '-ed'")
        XCTAssertTrue(h.spoken.contains("looked"))

        let r = stuckHint(for: "round")
        XCTAssertEqual(r.chunks[r.trickyIndex!], "ou")
    }

    func testSilentEMarksTheFinalE() {
        let h = stuckHint(for: "name")
        XCTAssertEqual(h.trickyIndex, h.chunks.count - 1)
        XCTAssertEqual(h.chunks.last, "e")
    }

    func testWordWithoutPatternStillGetsHelp() {
        let h = stuckHint(for: "drum")
        XCTAssertNil(h.patternLabel)
        XCTAssertNil(h.trickyIndex)
        XCTAssertEqual(h.chunks, ["d", "r", "u", "m"])
        XCTAssertFalse(h.title.isEmpty)
    }

    func testHintCopyHasNoEmDash() {
        for w in ["looked", "name", "drum", "thought", "rain"] {
            let h = stuckHint(for: w)
            XCTAssertFalse(h.title.contains("\u{2014}"))
            XCTAssertFalse(h.spoken.contains("\u{2014}"))
        }
    }

    func testStallDetectorFiresAfterSilenceOncePerWord() {
        var d = StallDetector(stallSeconds: 3, maxHelpsPerPage: 3)
        XCTAssertNil(d.update(signature: "2|the", wordsHeard: 2, currentIndex: 2, now: 0))
        XCTAssertNil(d.update(signature: "2|the", wordsHeard: 2, currentIndex: 2, now: 2.9))
        XCTAssertEqual(d.update(signature: "2|the", wordsHeard: 2, currentIndex: 2, now: 3.1), 2)
        XCTAssertNil(d.update(signature: "2|the", wordsHeard: 2, currentIndex: 2, now: 9), "same word only once")
    }

    func testStallDetectorWaitsForReadingToStartAndCapsHelps() {
        var d = StallDetector(stallSeconds: 1, maxHelpsPerPage: 2)
        XCTAssertNil(d.update(signature: "0|", wordsHeard: 0, currentIndex: 0, now: 0))
        XCTAssertNil(d.update(signature: "0|", wordsHeard: 0, currentIndex: 0, now: 5), "not before any words")
        for (i, word) in [1, 2, 3].enumerated() {
            let t = Double(i) * 10 + 10
            _ = d.update(signature: "s\(word)", wordsHeard: word, currentIndex: word, now: t)
            let fired = d.update(signature: "s\(word)", wordsHeard: word, currentIndex: word, now: t + 2)
            XCTAssertEqual(fired, i < 2 ? word : nil)
        }
        d.reset()
        XCTAssertTrue(d.helped.isEmpty)
    }

    func testNewSpeechResetsTheTimer() {
        var d = StallDetector(stallSeconds: 3)
        _ = d.update(signature: "a", wordsHeard: 1, currentIndex: 1, now: 0)
        _ = d.update(signature: "b", wordsHeard: 1, currentIndex: 1, now: 2.5)
        XCTAssertNil(d.update(signature: "b", wordsHeard: 1, currentIndex: 1, now: 4))
        XCTAssertEqual(d.update(signature: "b", wordsHeard: 1, currentIndex: 1, now: 5.6), 1)
    }
}
