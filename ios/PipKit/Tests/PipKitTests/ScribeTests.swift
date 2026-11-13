import XCTest
@testable import PipKit

final class ScribeCodecTests: XCTestCase {
    func testURLAsksForManualCommitsAndTimestamps() throws {
        let url = ScribeURL.make(token: "tok_123")
        let c = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(c.scheme, "wss")
        XCTAssertEqual(c.host, "api.elevenlabs.io")
        XCTAssertEqual(c.path, "/v1/speech-to-text/realtime")
        let q = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(q["token"], "tok_123")
        XCTAssertEqual(q["model_id"], ScribeURL.model)
        XCTAssertEqual(q["audio_format"], "pcm_16000")
        XCTAssertEqual(q["commit_strategy"], "manual")
        XCTAssertEqual(q["include_timestamps"], "true")
        XCTAssertEqual(q["language_code"], "en")
    }

    func testURLNeverBiasesTowardTheStory() {
        let query = ScribeURL.make(token: "t").query ?? ""
        XCTAssertFalse(query.contains("keyterms"))
        XCTAssertFalse(query.contains("no_verbatim"))
    }

    func testEncodeChunk() throws {
        let pcm = Data([0x01, 0x00, 0xFF, 0x7F])
        let json = ScribeCodec.encodeChunk(pcm16: pcm, commit: false)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(obj["message_type"] as? String, "input_audio_chunk")
        XCTAssertEqual(obj["commit"] as? Bool, false)
        XCTAssertEqual(obj["sample_rate"] as? Int, 16000)
        XCTAssertEqual(Data(base64Encoded: obj["audio_base_64"] as? String ?? ""), pcm)
    }

    func testEncodeFinalCommitMayBeEmpty() throws {
        let json = ScribeCodec.encodeChunk(pcm16: Data(), commit: true)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(obj["commit"] as? Bool, true)
        XCTAssertEqual(obj["audio_base_64"] as? String, "")
    }

    func testDecodeSessionStartedAndPartials() {
        let started = #"{"message_type":"session_started","session_id":"sess_sample","config":{"sample_rate":16000,"model_id":"scribe_v3_live","include_timestamps":true,"keyterms":[],"no_verbatim":false}}"#
        XCTAssertEqual(ScribeCodec.decode(started), .sessionStarted)
        XCTAssertEqual(ScribeCodec.decode(#"{"message_type":"partial_transcript","text":"The little, um, the"}"#),
                       .partial("The little, um, the"))
        XCTAssertEqual(ScribeCodec.decode(#"{"message_type":"partial_transcript","text":""}"#), .partial(""))
        XCTAssertEqual(ScribeCodec.decode(#"{"message_type":"committed_transcript","text":"He was as round as a drum."}"#),
                       .committedText("He was as round as a drum."))
    }

    func testDecodeCommittedWithTimestampsKeepsDisfluencies() throws {
        // Shape captured from a live scribe_v3_live session.
        let msg = #"""
        {"message_type":"committed_transcript_with_timestamps","text":"The little, um, the little","language_code":"en","words":[
         {"text":"The","start":0.5,"end":0.58,"type":"word","speaker_id":null,"logprob":-0.01,"characters":["T","h","e"],"channel_index":null},
         {"text":" ","start":0.58,"end":0.64,"type":"spacing","speaker_id":null,"logprob":0,"characters":[" "],"channel_index":null},
         {"text":"little,","start":0.64,"end":0.92,"type":"word","speaker_id":null,"logprob":-0.2,"characters":null,"channel_index":null},
         {"text":"um,","start":1.24,"end":1.42,"type":"word","speaker_id":null,"logprob":-0.5,"characters":null,"channel_index":null},
         {"text":"the","start":1.7,"end":1.78,"type":"word","speaker_id":null,"logprob":-0.1,"characters":null,"channel_index":null},
         {"text":"little","start":1.84,"end":2,"type":"word","speaker_id":null,"logprob":-0.1,"characters":null,"channel_index":null}]}
        """#
        guard case .committed(let text, let words) = ScribeCodec.decode(msg) else { return XCTFail("not committed") }
        XCTAssertEqual(text, "The little, um, the little")
        XCTAssertEqual(words.map(\.text), ["The", "little,", "um,", "the", "little"])
        XCTAssertEqual(words[2].start, 1.24, accuracy: 1e-9)
        XCTAssertEqual(words[4].end, 2, accuracy: 1e-9)
    }

    func testDecodeCommittedWithNullWords() {
        let msg = #"{"message_type":"committed_transcript_with_timestamps","text":"","language_code":null,"words":null}"#
        XCTAssertEqual(ScribeCodec.decode(msg), .committed("", []))
    }

    func testDecodeWarningAndErrors() {
        XCTAssertEqual(ScribeCodec.decode(#"{"message_type":"warning","warning":"Audio is clipping"}"#),
                       .warning("Audio is clipping"))
        XCTAssertEqual(ScribeCodec.decode(#"{"message_type":"auth_error","error":"Invalid token"}"#),
                       .error(code: "auth_error", message: "Invalid token"))
        XCTAssertEqual(ScribeCodec.decode(#"{"message_type":"rate_limited","error":"Slow down"}"#),
                       .error(code: "rate_limited", message: "Slow down"))
        XCTAssertEqual(ScribeCodec.decode(#"{"message_type":"insufficient_audio_activity","error":"x"}"#),
                       .error(code: "insufficient_audio_activity", message: "x"))
        XCTAssertEqual(ScribeCodec.decode(#"{"message_type":"brand_new_error","error":"x"}"#),
                       .error(code: "brand_new_error", message: "x"))
    }

    func testDecodeIgnoresUnknownAndGarbage() {
        XCTAssertEqual(ScribeCodec.decode(#"{"message_type":"committed_transcript_entities","entities":[]}"#), .ignored)
        XCTAssertEqual(ScribeCodec.decode("not json"), .ignored)
        XCTAssertEqual(ScribeCodec.decode(#"{"text":"no type"}"#), .ignored)
    }

    func testErrorSentencesArePlain() {
        for code in ScribeCodec.errorTypes.sorted() + ["something_new"] {
            let s = ScribeCodec.sentence(forError: code)
            XCTAssertTrue(s.hasSuffix("."), code)
            XCTAssertFalse(s.contains("\u{2014}"), code)
            XCTAssertFalse(s.contains("_"), code)
        }
        XCTAssertEqual(ScribeCodec.sentence(forError: "rate_limited"), "The listening service is busy. Try again in a moment.")
    }
}

final class ScribeTranscriptTests: XCTestCase {
    /// Largest silence between consecutive words.
    private func maxGap(_ words: [TimedWord]) -> Double {
        zip(words, words.dropFirst()).map { $1.start - $0.end }.max() ?? 0
    }

    func testCommittedWordsAreOffsetToListenerTime() {
        var b = ScribeTranscriptBuilder(audioOffset: 0.4)
        b.apply(.committedText("The elephant's name"), at: 3)
        b.apply(.committed("The elephant's name", [
            TimedWord(text: "The", start: 0.5, end: 0.6),
            TimedWord(text: "elephant's", start: 0.7, end: 1.2),
            TimedWord(text: "name", start: 1.2, end: 1.4),
        ]), at: 3.1)
        let t = b.final
        XCTAssertEqual(t.text, "The elephant's name")
        XCTAssertEqual(t.words.map(\.start), [0.9, 1.1, 1.6].map { $0 }, accuracy: 1e-9)
        XCTAssertFalse(b.hasUntimedSpeech)
        XCTAssertEqual(b.timestampedSegments, 1)
    }

    func testPartialWordsAreStampedOnArrivalWithoutPilingUp() {
        var b = ScribeTranscriptBuilder()
        b.apply(.partial("The elephant's name"), at: 2.0)
        let words = b.live.words
        XCTAssertEqual(words.map(\.text), ["The", "elephant's", "name"])
        XCTAssertEqual(Set(words.map(\.start)).count, 3, "a burst is spread out, not stacked")
        XCTAssertLessThanOrEqual(words.last!.end, 2.0 - b.arrivalLag + 1e-9)
        XCTAssertLessThan(maxGap(words), 0.1)
    }

    func testRevisedPartialKeepsEarlierStamps() {
        var b = ScribeTranscriptBuilder()
        b.apply(.partial("The Little"), at: 1.0)
        let first = b.live.words
        b.apply(.partial("The little, um, the"), at: 2.0)
        let second = b.live.words
        XCTAssertEqual(second.map(\.text), ["The", "little,", "um,", "the"])
        XCTAssertEqual(second[0].start, first[0].start)
        XCTAssertEqual(second[1].start, first[1].start)
        XCTAssertGreaterThan(second[2].start, first[1].start)
    }

    func testSteadyReadingShowsNoFalsePausesButARealPauseShows() {
        // Partial arrival times from a live scribe_v3_live run of the demo page.
        let steady: [(Double, String)] = [
            (1.05, "The"), (1.38, "The elephant"), (1.68, "The elephant's name"),
            (2.03, "The elephant's name was"), (2.40, "The elephant's name was Golu."),
            (2.71, "The elephant's name was Golu. He was"), (3.02, "The elephant's name was Golu. He was as round"),
        ]
        var b = ScribeTranscriptBuilder(audioOffset: 0.5)
        for (t, text) in steady { b.apply(.partial(text), at: t) }
        XCTAssertLessThan(maxGap(b.live.words), 0.8, "network rhythm must not look like hesitation")

        // The reader stops for two seconds, then carries on.
        b.apply(.partial("The elephant's name was Golu. He was as round as a drum."), at: 3.6)
        b.apply(.partial("The elephant's name was Golu. He was as round as a drum. He"), at: 6.0)
        let words = b.live.words
        let gap = words[words.count - 1].start - words[words.count - 2].end
        XCTAssertGreaterThan(gap, 1.5)
    }

    func testTrailingFragmentHiddenLiveButKeptInFinal() {
        var b = ScribeTranscriptBuilder()
        b.apply(.partial("He looked like a ball of-"), at: 3)
        XCTAssertEqual(b.live.words.last?.text, "ball")
        XCTAssertEqual(b.final.words.last?.text, "of")
        XCTAssertEqual(b.partialText, "He looked like a ball of-")
    }

    func testSettledTextShowsUntilTimestampsArrive() {
        var b = ScribeTranscriptBuilder()
        b.apply(.partial("He was as round as a"), at: 5.5)
        b.apply(.committedText("He was as round as a drum."), at: 5.7)
        XCTAssertTrue(b.hasUntimedSpeech)
        XCTAssertEqual(b.live.words.count, 6, "keeps the partial's stamps on screen")
        XCTAssertEqual(b.partialText, "")
        b.apply(.committed("He was as round as a drum.", [
            TimedWord(text: "He", start: 4.12, end: 4.22),
            TimedWord(text: "drum.", start: 5.12, end: 5.48),
        ]), at: 5.72)
        XCTAssertFalse(b.hasUntimedSpeech)
        XCTAssertEqual(b.live.words.map(\.text), ["He", "drum."])
    }

    func testTwoSegmentsJoinInOrder() {
        var b = ScribeTranscriptBuilder(audioOffset: 1)
        b.apply(.committedText("The little elephant."), at: 3.5)
        b.apply(.committed("The little elephant.", [
            TimedWord(text: "The", start: 0.5, end: 0.6),
            TimedWord(text: "little", start: 0.6, end: 0.9),
            TimedWord(text: "elephant.", start: 1.0, end: 1.4),
        ]), at: 3.6)
        b.apply(.partial("He was"), at: 5)
        XCTAssertEqual(b.live.text, "The little elephant. He was")
        XCTAssertGreaterThanOrEqual(b.live.words[3].start, b.live.words[2].end)
        b.apply(.committedText("He was round."), at: 6)
        b.apply(.committed("He was round.", [
            TimedWord(text: "He", start: 4.1, end: 4.2),
            TimedWord(text: "was", start: 4.3, end: 4.4),
            TimedWord(text: "round.", start: 4.5, end: 4.9),
        ]), at: 6.1)
        let t = b.final
        XCTAssertEqual(t.text, "The little elephant. He was round.")
        XCTAssertEqual(t.words.map(\.text), ["The", "little", "elephant.", "He", "was", "round."])
        XCTAssertEqual(t.words[3].start, 5.1, accuracy: 1e-9)
    }

    func testFallbackSpacesTheLastPartialEvenly() {
        var b = ScribeTranscriptBuilder()
        b.apply(.partial("He looked"), at: 2)
        b.apply(.partial("He looked like a ball"), at: 4)
        let t = b.final
        XCTAssertEqual(t.text, "He looked like a ball")
        XCTAssertEqual(t.words.count, 5)
        let starts = t.words.map(\.start)
        let steps = zip(starts, starts.dropFirst()).map { $1 - $0 }
        for s in steps { XCTAssertEqual(s, steps[0], accuracy: 1e-9) }
        XCTAssertGreaterThan(steps[0], 0)
    }

    func testFallbackUsesSettledTextWhenTimestampsNeverCome() {
        var b = ScribeTranscriptBuilder()
        b.apply(.partial("ball of cot"), at: 3)
        b.apply(.committedText("ball of cottle."), at: 3.2)
        let t = b.final
        XCTAssertEqual(t.text, "ball of cottle.")
        XCTAssertEqual(t.words.map(\.text), ["ball", "of", "cottle."])
    }

    func testEmptyPartialClearsTheOpenSegment() {
        var b = ScribeTranscriptBuilder()
        b.apply(.partial(""), at: 1)
        XCTAssertEqual(b.live, .empty)
        XCTAssertEqual(b.final, .empty)
        XCTAssertFalse(b.hasUntimedSpeech)
    }

    func testCommitOverSilenceIsAnsweredInEitherOrder() {
        // Observed live: a commit over silence answered timestamps first.
        var b = ScribeTranscriptBuilder()
        b.apply(.committedText("He was round."), at: 3)
        b.apply(.committed("He was round.", [TimedWord(text: "He", start: 1, end: 1.2)]), at: 3.1)
        b.apply(.committed("", []), at: 6)
        b.apply(.committedText(""), at: 6.01)
        XCTAssertEqual(b.timestampedSegments, 2)
        XCTAssertFalse(b.hasUntimedSpeech)
        XCTAssertEqual(b.final.text, "He was round.")
        XCTAssertEqual(b.final.words.count, 1)
        // The next segment still settles normally.
        b.apply(.partial("He looked"), at: 8)
        b.apply(.committedText("He looked."), at: 9)
        XCTAssertTrue(b.hasUntimedSpeech)
        b.apply(.committed("He looked.", [TimedWord(text: "He", start: 7, end: 7.1), TimedWord(text: "looked.", start: 7.2, end: 7.5)]), at: 9.1)
        XCTAssertEqual(b.final.text, "He was round. He looked.")
        XCTAssertEqual(b.final.words.count, 3)
    }

    func testTimestampsBeforeTextDoNotDuplicateWords() {
        var b = ScribeTranscriptBuilder()
        b.apply(.partial("ball of cottle"), at: 3)
        b.apply(.committed("ball of cottle.", [
            TimedWord(text: "ball", start: 2.0, end: 2.2),
            TimedWord(text: "of", start: 2.3, end: 2.4),
            TimedWord(text: "cottle.", start: 2.5, end: 2.9),
        ]), at: 3.2)
        b.apply(.committedText("ball of cottle."), at: 3.21)
        XCTAssertEqual(b.live.words.map(\.text), ["ball", "of", "cottle."])
        XCTAssertEqual(b.final.text, "ball of cottle.")
        XCTAssertFalse(b.hasUntimedSpeech)
    }

    func testLiveTextSpansSegments() {
        var b = ScribeTranscriptBuilder()
        b.apply(.partial("The little"), at: 1)
        XCTAssertEqual(b.liveText, "The little")
        b.apply(.committedText("The little elephant."), at: 2)
        XCTAssertEqual(b.liveText, "The little elephant.")
        b.apply(.committed("The little elephant.", [TimedWord(text: "The", start: 0.1, end: 0.2)]), at: 2.1)
        b.apply(.partial("He was"), at: 3)
        XCTAssertEqual(b.liveText, "The little elephant. He was")
    }
}

private func XCTAssertEqual(_ a: [Double], _ b: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}
