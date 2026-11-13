import XCTest
@testable import PipKit

final class PipVoiceTests: XCTestCase {
    private let mistake = PlantedMistake(wordIndex: 4, sentenceIndex: 0, correct: "shook", misread: "shock",
                                         speakAs: "shock", patternId: "oo", reaction: "Shook! Thank you, teacher!")

    func testCatchWhenCorrectWordSaid() {
        XCTAssertTrue(detectCatch(transcript: "shook", mistake: mistake))
        XCTAssertTrue(detectCatch(transcript: "no, it says shook", mistake: mistake))
    }

    func testNoCatchForEmptyYesOrMisreading() {
        XCTAssertFalse(detectCatch(transcript: "", mistake: mistake))
        XCTAssertFalse(detectCatch(transcript: "yes", mistake: mistake))
        XCTAssertFalse(detectCatch(transcript: "shock", mistake: mistake))
    }

    func testBareObjection() {
        XCTAssertTrue(isBareObjection(transcript: .synthetic("no that's wrong"), mistake: mistake))
        XCTAssertFalse(isBareObjection(transcript: .synthetic("no it says shook"), mistake: mistake))
        XCTAssertFalse(isBareObjection(transcript: .synthetic("yes"), mistake: mistake))
    }

    func testLinesStripTags() {
        XCTAssertEqual(PipLine.likeThis.text, "Ohh! Like this?")
        XCTAssertFalse(PipLine.allCases.contains { $0.text.contains("[") })
        XCTAssertEqual(PipVoiceText.stripAudioTags("[gasps] Oh no! [scared] What?"), "Oh no! What?")
    }

    func testWordIndexAtTime() {
        let starts = [0.0, 0.4, 0.9]
        XCTAssertNil(PipVoiceText.wordIndex(at: -0.1, starts: starts))
        XCTAssertEqual(PipVoiceText.wordIndex(at: 0.5, starts: starts), 1)
        XCTAssertEqual(PipVoiceText.wordIndex(at: 2, starts: starts), 2)
    }
}
