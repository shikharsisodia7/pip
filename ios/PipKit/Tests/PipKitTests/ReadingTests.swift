import XCTest
@testable import PipKit

private func transcript(_ text: String) -> Transcript {
    Transcript(text: text, words: text.split(whereSeparator: { $0.isWhitespace }).enumerated().map { i, word in
        TimedWord(text: String(word), start: Double(i), end: Double(i) + 0.5)
    })
}

final class ReadingAlignmentTests: XCTestCase {
    func testPerfectReadPreservesPageIndexesAndTimestamps() {
        XCTAssertEqual(alignWords(expectedText: "The cat sat.", transcript: transcript("The cat sat.")),
                       AlignmentResult(words: [
                        AlignedWord(index: 0, expected: "the", status: .correct, start: 0, end: 0.5),
                        AlignedWord(index: 1, expected: "cat", status: .correct, start: 1, end: 1.5),
                        AlignedWord(index: 2, expected: "sat", status: .correct, start: 2, end: 2.5),
                       ], insertions: []))
    }

    func testSubstitutionIsNormalizedWithoutShiftingLaterWords() {
        let result = alignWords(expectedText: "The cat sat.", transcript: transcript("The CAP, sat."))
        XCTAssertEqual(result.words.map(\.status), [.correct, .substitution, .correct])
        XCTAssertEqual(result.words[1], AlignedWord(index: 1, expected: "cat", status: .substitution,
                                                   said: "cap", start: 1, end: 1.5))
        XCTAssertTrue(result.insertions.isEmpty)
    }

    func testOmissionDoesNotBorrowNextWordOrTimestamps() {
        let result = alignWords(expectedText: "The little cat sat.", transcript: transcript("The cat sat."))
        XCTAssertEqual(result.words[1], AlignedWord(index: 1, expected: "little", status: .omission))
        XCTAssertEqual(result.words[2], AlignedWord(index: 2, expected: "cat", status: .correct, start: 1, end: 1.5))
        XCTAssertEqual(result.words[3].status, .correct)
    }

    func testExtraWordAfterPageIsAnInsertion() {
        let result = alignWords(expectedText: "The cat sat.", transcript: transcript("The cat sat down."))
        XCTAssertTrue(result.words.allSatisfy { $0.status == .correct })
        XCTAssertEqual(result.insertions, [Insertion(afterIndex: 2, said: "down")])
    }

    func testImmediateSelfCorrectionUsesCorrectedWordTimingAndCountsAsCorrect() {
        let result = alignWords(expectedText: "The cat sat.", transcript: transcript("The dog cat sat."))
        XCTAssertEqual(result.words[1], AlignedWord(index: 1, expected: "cat", status: .selfCorrected,
                                                   said: "dog", start: 2, end: 2.5))
        XCTAssertEqual(result.words[2].status, .correct)
        XCTAssertTrue(result.insertions.isEmpty)
        let metrics = computeMetrics(result)
        XCTAssertEqual(metrics.accuracyPct, 100)
        XCTAssertEqual(metrics.wordsCorrect, 3)
        XCTAssertEqual(metrics.selfCorrections, 1)
    }

    func testFalseStartsIncludingFuzzyPrefixesAreSelfCorrections() {
        for attempt in ["br-", "brigh-"] {
            let result = alignWords(expectedText: "A bright moon.", transcript: transcript("A \(attempt) bright moon."))
            XCTAssertEqual(result.words[1].status, .selfCorrected, attempt)
            XCTAssertEqual(result.words[1].said, normalizeToken(attempt), attempt)
            XCTAssertEqual(result.words[1].start, 2, attempt)
            XCTAssertTrue(result.insertions.isEmpty, attempt)
        }
    }

    func testRepeatedCorrectWordsAreForgiven() {
        let result = alignWords(expectedText: "The cat sat.", transcript: transcript("The the the cat cat sat sat."))
        XCTAssertEqual(result.words.map(\.status), [.correct, .correct, .correct])
        XCTAssertEqual(result.words.map(\.start), [0, 3, 5])
        XCTAssertTrue(result.insertions.isEmpty)
        XCTAssertEqual(computeMetrics(result).selfCorrections, 0)
    }

    func testRepeatedWordsOnPageRemainDistinct() {
        let result = alignWords(expectedText: "A very very quiet night.",
                                transcript: transcript("A very very very quiet night."))
        XCTAssertEqual(result.words.count, 5)
        XCTAssertTrue(result.words.allSatisfy { $0.status == .correct })
        XCTAssertTrue(result.insertions.isEmpty)
    }

    func testCorrectionFollowedByRepeatsStaysOneCorrection() {
        let result = alignWords(expectedText: "The cat sat.", transcript: transcript("The dog cat cat cat sat."))
        XCTAssertEqual(result.words.map(\.status), [.correct, .selfCorrected, .correct])
        XCTAssertEqual(result.words[1].start, 2)
        XCTAssertTrue(result.insertions.isEmpty)
    }

    func testGapLongerThanThresholdIsAHesitation() {
        let result = alignWords(expectedText: "The cat.", transcript: Transcript(text: "The cat.", words: [
            TimedWord(text: "The", start: 10, end: 10.5),
            TimedWord(text: "cat", start: 12, end: 12.5),
        ]))
        XCTAssertNil(result.words[0].hesitationBeforeSec)
        XCTAssertEqual(result.words[1].hesitationBeforeSec, 1.5)
    }

    func testExactlyThresholdIsNotAHesitation() {
        for start in [1.2, 1.2 + 0.5e-9] {
            let result = alignWords(expectedText: "The cat.", transcript: Transcript(text: "The cat.", words: [
                TimedWord(text: "The", start: 0, end: 0.4),
                TimedWord(text: "cat", start: start, end: 1.5),
            ]))
            XCTAssertNil(result.words[1].hesitationBeforeSec)
        }
    }

    func testHesitationUsesPreviousSpokenWordIncludingRepeats() {
        let result = alignWords(expectedText: "The cat.", transcript: Transcript(text: "The the cat.", words: [
            TimedWord(text: "The", start: 0, end: 0.2),
            TimedWord(text: "the", start: 0.3, end: 0.9),
            TimedWord(text: "cat", start: 1.2, end: 1.5),
        ]))
        XCTAssertNil(result.words[1].hesitationBeforeSec)
    }

    func testCorrectionHesitationUsesIncorrectAttempt() {
        let result = alignWords(expectedText: "cat", transcript: Transcript(text: "dog cat", words: [
            TimedWord(text: "dog", start: 0, end: 0.5),
            TimedWord(text: "cat", start: 2, end: 2.5),
        ]))
        XCTAssertEqual(result.words[0].status, .selfCorrected)
        XCTAssertEqual(result.words[0].hesitationBeforeSec, 1.5)
    }

    func testContractionsMatchCurlyStraightOrMissingApostrophes() {
        let result = alignWords(expectedText: "Don’t worry, it’s quiet.", transcript: transcript("dont worry it's quiet"))
        XCTAssertEqual(result.words.map(\.expected), ["don't", "worry", "it's", "quiet"])
        XCTAssertTrue(result.words.allSatisfy { $0.status == .correct })
    }

    func testDisplayIndexesIgnorePunctuationOnlyTokens() {
        let result = alignWords(expectedText: "\"Look!\" ... A cat, ran.", transcript: transcript("LOOK ... a cat ran!"))
        XCTAssertEqual(result.words.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(result.words.map(\.expected), ["look", "a", "cat", "ran"])
        XCTAssertEqual(result.words.map(\.start), [0, 2, 3, 4])
        XCTAssertTrue(result.words.allSatisfy { $0.status == .correct })
        XCTAssertTrue(result.insertions.isEmpty)
    }

    func testNumbersNormalizeOnBothSides() {
        let result = alignWords(expectedText: "2 cats saw three birds.", transcript: transcript("two cats saw 3 birds"))
        XCTAssertEqual(result.words.map(\.expected), ["two", "cats", "saw", "three", "birds"])
        XCTAssertTrue(result.words.allSatisfy { $0.status == .correct })
    }

    func testSharedFuzzyRuleDoesNotForgiveShortWordSubstitutions() {
        let result = alignWords(expectedText: "A bright cat.", transcript: transcript("A brigt cap."))
        XCTAssertEqual(result.words.map(\.status), [.correct, .correct, .substitution])
    }

    func testFuzzyMatchRequiresBothTokensToHaveFiveCharactersAndOnlyOneEdit() {
        let result = alignWords(expectedText: "quiet bright", transcript: transcript("quit brent"))
        XCTAssertEqual(result.words.map(\.status), [.substitution, .substitution])
    }

    func testEmptyTranscriptOmitsEveryExpectedWord() {
        XCTAssertEqual(alignWords(expectedText: "The cat.", transcript: .empty), AlignmentResult(words: [
            AlignedWord(index: 0, expected: "the", status: .omission),
            AlignedWord(index: 1, expected: "cat", status: .omission),
        ], insertions: []))
    }

    func testLongerTranscriptKeepsInsertionsInOrder() {
        let result = alignWords(expectedText: "The cat.", transcript: transcript("The cat ran past the dog."))
        XCTAssertTrue(result.words.allSatisfy { $0.status == .correct })
        XCTAssertEqual(result.insertions, ["ran", "past", "the", "dog"].map { Insertion(afterIndex: 1, said: $0) })
    }

    func testEmptyPageUsesMinusOneForInsertionIndex() {
        XCTAssertEqual(alignWords(expectedText: "", transcript: transcript("hello Pip")), AlignmentResult(words: [], insertions: [
            Insertion(afterIndex: -1, said: "hello"), Insertion(afterIndex: -1, said: "pip"),
        ]))
        XCTAssertEqual(alignWords(expectedText: "", transcript: .empty), AlignmentResult(words: [], insertions: []))
    }

    func testEntirelyWrongReadIsSubstitutions() {
        let result = alignWords(expectedText: "The cat sat.", transcript: transcript("Red dog ran."))
        XCTAssertEqual(result.words.map(\.status), [.substitution, .substitution, .substitution])
        XCTAssertEqual(result.words.map(\.said), ["red", "dog", "ran"])
        XCTAssertTrue(result.insertions.isEmpty)
    }

    func testWrongWordBeforeRepeatedPageWordPreservesDistinctOccurrences() {
        let result = alignWords(expectedText: "cat cat", transcript: transcript("dog cat"))
        XCTAssertEqual(result.words.map(\.status), [.substitution, .correct])
    }

    func testPartialReadLeavesTrailingWordsOmittedAndLiveMarksPending() {
        let page = "The cat sat on the mat."
        let tokens = tokenizeDisplay(page)
        for count in 0...tokens.count {
            let spoken = transcript(tokens.prefix(count).map(\.display).joined(separator: " "))
            let result = alignWords(expectedText: page, transcript: spoken)
            XCTAssertEqual(result.words.map(\.status),
                           Array(repeating: WordStatus.correct, count: count)
                            + Array(repeating: WordStatus.omission, count: tokens.count - count))
            XCTAssertEqual(result.words.lastIndex { $0.status != .omission }, count == 0 ? nil : count - 1)
            XCTAssertTrue(result.words.dropFirst(count).allSatisfy { $0.start == nil && $0.end == nil && $0.said == nil })
            let unreadMarks: [WordMark] = count < tokens.count
                ? [.current] + Array(repeating: .pending, count: tokens.count - count - 1) : []
            XCTAssertEqual(liveMarks(expectedText: page, transcript: spoken),
                           Array(repeating: WordMark.correct, count: count) + unreadMarks)
        }
    }

    func testPartialReadWithErrorAndPausePreservesFrontier() {
        let page = "The cat sat on the mat."
        let spoken = Transcript(text: "the cot sat", words: [
            TimedWord(text: "the", start: 0, end: 0.3),
            TimedWord(text: "cot", start: 0.4, end: 0.7),
            TimedWord(text: "sat", start: 2, end: 2.3),
        ])
        let result = alignWords(expectedText: page, transcript: spoken)
        XCTAssertEqual(result.words.map(\.status), [.correct, .substitution, .correct, .omission, .omission, .omission])
        XCTAssertEqual(result.words.lastIndex { $0.status != .omission }, 2)
        XCTAssertEqual(liveMarks(expectedText: page, transcript: spoken),
                       [.correct, .missed, .hesitant, .current, .pending, .pending])
        XCTAssertEqual(liveMarks(expectedText: page, transcript: spoken, final: true),
                       [.correct, .missed, .hesitant, .missed, .missed, .missed])
    }

    func testPartialReadWithInternalOmissionPreservesFrontier() {
        let page = "The little cat sat on a mat."
        let spoken = transcript("The cat sat")
        let result = alignWords(expectedText: page, transcript: spoken)
        XCTAssertEqual(result.words.map(\.status), [.correct, .omission, .correct, .correct, .omission, .omission, .omission])
        XCTAssertEqual(liveMarks(expectedText: page, transcript: spoken),
                       [.correct, .missed, .correct, .correct, .current, .pending, .pending])
    }

    func testPartialReadPreservesRepeatedPageOccurrences() {
        let result = alignWords(expectedText: "A very very quiet night.", transcript: transcript("A very very"))
        XCTAssertEqual(result.words.map(\.status), [.correct, .correct, .correct, .omission, .omission])
        XCTAssertEqual(result.words.map(\.start), [0, 1, 2, nil, nil])
        XCTAssertTrue(result.insertions.isEmpty)
    }

    func testPunctuationOnlyTranscriptLeavesAllWordsUnread() {
        let result = alignWords(expectedText: "The cat.", transcript: transcript("... ! --"))
        XCTAssertEqual(result.words.map(\.status), [.omission, .omission])
        XCTAssertTrue(result.insertions.isEmpty)
    }

    func testAlignmentUsesTimedWordsInsteadOfTranscriptSummary() {
        let result = alignWords(expectedText: "The cat.", transcript: Transcript(text: "The dog.", words: [
            TimedWord(text: "The", start: 0, end: 0.5),
            TimedWord(text: "cat", start: 1, end: 1.5),
        ]))
        XCTAssertEqual(result.words.map(\.status), [.correct, .correct])
    }

    func testBundledDemoTranscriptAgainstFirstBookPage() throws {
        // Sample from App/Fixtures/book.json and page1-demo.json, copied for package-only tests.
        // Playtime, Sanjiv Jaiswal 'Sanjay', translated by Manisha Chaudhry, illustrated by Ajit Narayan.
        // Pratham Books StoryWeaver, CC BY 4.0: https://storyweaver.org.in/stories/375-playtime
        let page = "The little elephant's name was Golu. He was as round as a drum. The little rabbit was called Chhotu. He looked like a ball of cotton."
        let json = #"""
        {
          "text": "The elephant's name was Golu. He was as round as a drum. The little rabbit was named Chhotu. He looked like a ball of cotton.",
          "words": [
            { "text": "The", "start": 0.2, "end": 0.4 },
            { "text": "elephant's", "start": 0.5, "end": 1.2 },
            { "text": "name", "start": 1.3, "end": 1.65 },
            { "text": "was", "start": 1.75, "end": 2.0 },
            { "text": "Golu.", "start": 2.1, "end": 2.65 },
            { "text": "He", "start": 3.0, "end": 3.2 },
            { "text": "was", "start": 3.3, "end": 3.55 },
            { "text": "as", "start": 3.65, "end": 3.85 },
            { "text": "round", "start": 3.95, "end": 4.4 },
            { "text": "as", "start": 4.5, "end": 4.7 },
            { "text": "a", "start": 4.8, "end": 4.95 },
            { "text": "drum.", "start": 5.05, "end": 5.5 },
            { "text": "The", "start": 5.85, "end": 6.05 },
            { "text": "little", "start": 6.15, "end": 6.5 },
            { "text": "rabbit", "start": 6.6, "end": 7.1 },
            { "text": "was", "start": 7.2, "end": 7.45 },
            { "text": "named", "start": 7.55, "end": 8.0 },
            { "text": "Chhotu.", "start": 8.1, "end": 8.75 },
            { "text": "He", "start": 10.75, "end": 10.95 },
            { "text": "looked", "start": 11.05, "end": 11.5 },
            { "text": "like", "start": 11.6, "end": 11.95 },
            { "text": "a", "start": 12.05, "end": 12.2 },
            { "text": "ball", "start": 12.3, "end": 12.7 },
            { "text": "of", "start": 12.8, "end": 13.0 },
            { "text": "cotton.", "start": 13.1, "end": 13.65 }
          ]
        }
        """#
        let sample = try JSONDecoder().decode(Transcript.self, from: Data(json.utf8))
        let result = alignWords(expectedText: page, transcript: sample)
        XCTAssertEqual(result.words.map(\.expected), tokenizeDisplay(page).map(\.norm))
        XCTAssertEqual(result.words.map(\.index), Array(0..<26))
        XCTAssertEqual(result.words.filter { $0.status == .omission }, [
            AlignedWord(index: 1, expected: "little", status: .omission),
        ])
        XCTAssertEqual(result.words.filter { $0.status == .substitution }, [
            AlignedWord(index: 17, expected: "called", status: .substitution, said: "named", start: 7.55, end: 8),
        ])
        XCTAssertFalse(fuzzyEqual("called", "named"))
        XCTAssertEqual(result.words[19].hesitationBeforeSec, 2)
        XCTAssertTrue(result.insertions.isEmpty)
        XCTAssertEqual(computeMetrics(result), ReadingMetrics(
            wcpm: 107, accuracyPct: 92, wordsCorrect: 24, wordsTotal: 26,
            durationSec: 13.45, hesitations: 1, selfCorrections: 0
        ))
    }
}

final class ReadingMetricsTests: XCTestCase {
    func testWCPMUsesElapsedTimeFromFirstAlignedStartToLastEnd() {
        let alignment = alignWords(expectedText: "The cat sat.", transcript: Transcript(text: "The cap sat.", words: [
            TimedWord(text: "The", start: 5, end: 5.5),
            TimedWord(text: "cap", start: 6, end: 6.5),
            TimedWord(text: "sat", start: 7, end: 7.5),
        ]))
        XCTAssertEqual(computeMetrics(alignment), ReadingMetrics(
            wcpm: 48, accuracyPct: 67, wordsCorrect: 2, wordsTotal: 3,
            durationSec: 2.5, hesitations: 0, selfCorrections: 0
        ))
    }

    func testCorrectedWordsCountInAccuracyAndPaceButInsertionsDoNot() {
        let alignment = AlignmentResult(words: [
            AlignedWord(index: 0, expected: "the", status: .correct, start: 0, end: 1),
            AlignedWord(index: 1, expected: "cat", status: .selfCorrected, said: "dog", start: 3, end: 4,
                        hesitationBeforeSec: 1.5),
            AlignedWord(index: 2, expected: "sat", status: .omission),
        ], insertions: [Insertion(afterIndex: 1, said: "down")])
        XCTAssertEqual(computeMetrics(alignment), ReadingMetrics(
            wcpm: 30, accuracyPct: 67, wordsCorrect: 2, wordsTotal: 3,
            durationSec: 4, hesitations: 1, selfCorrections: 1
        ))
    }

    func testBoundarySubstitutionsContributeToDuration() {
        let alignment = alignWords(expectedText: "The cat sat.", transcript: Transcript(text: "Red cat ran.", words: [
            TimedWord(text: "Red", start: 2, end: 3),
            TimedWord(text: "cat", start: 3, end: 4),
            TimedWord(text: "ran", start: 4, end: 8),
        ]))
        let metrics = computeMetrics(alignment)
        XCTAssertEqual(metrics.wordsCorrect, 1)
        XCTAssertEqual(metrics.durationSec, 6)
        XCTAssertEqual(metrics.wcpm, 10)
    }

    func testEmptyAlignmentReturnsZeroMetrics() {
        XCTAssertEqual(computeMetrics(AlignmentResult(words: [], insertions: [])), ReadingMetrics(
            wcpm: 0, accuracyPct: 0, wordsCorrect: 0, wordsTotal: 0,
            durationSec: 0, hesitations: 0, selfCorrections: 0
        ))
    }

    func testUnreadPageHasZeroPaceAndAccuracy() {
        XCTAssertEqual(computeMetrics(alignWords(expectedText: "The cat sat.", transcript: .empty)), ReadingMetrics(
            wcpm: 0, accuracyPct: 0, wordsCorrect: 0, wordsTotal: 3,
            durationSec: 0, hesitations: 0, selfCorrections: 0
        ))
    }

    func testZeroDurationKeepsCorrectWordCount() {
        let alignment = alignWords(expectedText: "cat", transcript: Transcript(text: "cat", words: [
            TimedWord(text: "cat", start: 2, end: 2),
        ]))
        let metrics = computeMetrics(alignment)
        XCTAssertEqual(metrics.wcpm, 0)
        XCTAssertEqual(metrics.durationSec, 0)
        XCTAssertEqual(metrics.accuracyPct, 100)
        XCTAssertEqual(metrics.wordsCorrect, 1)
    }

    func testMissingOrInvalidTimestampsDoNotInventDuration() {
        let alignment = AlignmentResult(words: [
            AlignedWord(index: 0, expected: "the", status: .correct),
            AlignedWord(index: 1, expected: "cat", status: .correct, start: 3, end: 2),
            AlignedWord(index: 2, expected: "sat", status: .correct, start: .nan, end: .infinity),
        ], insertions: [])
        let metrics = computeMetrics(alignment)
        XCTAssertEqual(metrics.wcpm, 0)
        XCTAssertEqual(metrics.durationSec, 0)
        XCTAssertEqual(metrics.accuracyPct, 100)
    }

    func testPaceUsesUnroundedDuration() {
        let alignment = alignWords(expectedText: "cat", transcript: Transcript(text: "cat", words: [
            TimedWord(text: "cat", start: 0, end: 0.334),
        ]))
        let metrics = computeMetrics(alignment)
        XCTAssertEqual(metrics.durationSec, 0.33)
        XCTAssertEqual(metrics.wcpm, 180)
    }

    func testOnlyHesitationsExceedingThresholdCount() {
        let alignment = AlignmentResult(words: [
            AlignedWord(index: 0, expected: "the", status: .correct, hesitationBeforeSec: 0.8),
            AlignedWord(index: 1, expected: "cat", status: .correct, hesitationBeforeSec: 1.2),
            AlignedWord(index: 2, expected: "sat", status: .correct, hesitationBeforeSec: 2),
            AlignedWord(index: 3, expected: "here", status: .correct, hesitationBeforeSec: 0.8 + 0.5e-9),
        ], insertions: [])
        XCTAssertEqual(computeMetrics(alignment).hesitations, 2)
    }

    func testOnlyCompleteFiniteTimestampPairsContributeToDuration() {
        let alignment = AlignmentResult(words: [
            AlignedWord(index: 0, expected: "a", status: .correct, start: -100),
            AlignedWord(index: 1, expected: "cat", status: .correct, end: 100),
            AlignedWord(index: 2, expected: "sat", status: .correct, start: 3, end: 2),
            AlignedWord(index: 3, expected: "by", status: .correct, start: -.infinity, end: 20),
            AlignedWord(index: 4, expected: "the", status: .correct, start: 10, end: .nan),
            AlignedWord(index: 5, expected: "mat", status: .correct, start: 5, end: 7),
        ], insertions: [])
        let metrics = computeMetrics(alignment)
        XCTAssertEqual(metrics.durationSec, 2)
        XCTAssertEqual(metrics.wcpm, 180)
        XCTAssertEqual(metrics.wordsCorrect, 6)
    }

    func testTimestampExtremaDoNotDependOnArrayOrder() {
        let alignment = AlignmentResult(words: [
            AlignedWord(index: 0, expected: "cat", status: .correct, start: 8, end: 10),
            AlignedWord(index: 1, expected: "sat", status: .correct, start: 2, end: 3),
        ], insertions: [])
        let metrics = computeMetrics(alignment)
        XCTAssertEqual(metrics.durationSec, 8)
        XCTAssertEqual(metrics.wcpm, 15)
    }

    func testHalfwayValuesRoundUpLikeTypeScript() {
        let alignment = AlignmentResult(words: [
            AlignedWord(index: 0, expected: "cat", status: .correct, start: 0, end: 0.125),
        ] + (1...7).map { AlignedWord(index: $0, expected: "sat", status: .omission) }, insertions: [])
        let metrics = computeMetrics(alignment)
        XCTAssertEqual(metrics.accuracyPct, 13)
        XCTAssertEqual(metrics.durationSec, 0.13)
        XCTAssertEqual(metrics.wcpm, 480)
    }
}
