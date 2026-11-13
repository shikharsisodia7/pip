// STUB, replaced by the real aligner (Needleman-Wunsch port of lib/reading/align.ts).
// Keep these two signatures exactly.

import Foundation

/// Aligns what the child said with the page text. One AlignedWord per page word
/// (tokenizeDisplay indexes), plus words said that are not on the page.
public func alignWords(expectedText: String, transcript: Transcript) -> AlignmentResult {
    let expected = tokenizeDisplay(expectedText)
    let said = transcript.words
    var words: [AlignedWord] = []
    var j = 0
    var prevEnd: Double?
    for (i, tok) in expected.enumerated() {
        if j < said.count {
            let w = said[j]
            let ok = fuzzyEqual(w.text, tok.norm)
            let gap = prevEnd.map { max(0, w.start - $0) }
            words.append(AlignedWord(index: i, expected: tok.norm, status: ok ? .correct : .substitution,
                                     said: normalizeToken(w.text), start: w.start, end: w.end,
                                     hesitationBeforeSec: gap))
            prevEnd = w.end
            j += 1
        } else {
            words.append(AlignedWord(index: i, expected: tok.norm, status: .omission))
        }
    }
    return AlignmentResult(words: words, insertions: [])
}

public func computeMetrics(_ alignment: AlignmentResult) -> ReadingMetrics {
    let total = alignment.words.count
    let correct = alignment.words.filter { $0.status == .correct || $0.status == .selfCorrected }.count
    let starts = alignment.words.compactMap(\.start), ends = alignment.words.compactMap(\.end)
    let duration = max(0, (ends.max() ?? 0) - (starts.min() ?? 0))
    let wcpm = duration > 0 ? Double(correct) / (duration / 60) : 0
    return ReadingMetrics(
        wcpm: wcpm.rounded(),
        accuracyPct: total > 0 ? (Double(correct) / Double(total) * 100).rounded() : 0,
        wordsCorrect: correct,
        wordsTotal: total,
        durationSec: duration,
        hesitations: alignment.words.filter { ($0.hesitationBeforeSec ?? 0) >= 0.8 }.count,
        selfCorrections: alignment.words.filter { $0.status == .selfCorrected }.count
    )
}
