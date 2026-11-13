// On-device versions of the server's reading diagnosis and mistake planner.
// Used when the server is unreachable, so any book works offline.

import Foundation

/// Finds the phonics pattern behind the words the child missed, from the alignment alone.
public func localDiagnosis(pageText: String, alignment: AlignmentResult) -> DiagnoseResponse {
    let missed = alignment.words.filter { $0.status == .substitution || $0.status == .omission }.map(\.expected)
    var best: (PhonicsPattern, [String])?
    for p in Patterns.all {
        let hits = missed.filter { p.test($0) }
        if !hits.isEmpty, hits.count > (best?.1.count ?? 0) { best = (p, hits) }
    }
    if let (p, hits) = best {
        let unique = Array(NSOrderedSet(array: hits)) as? [String] ?? hits
        return DiagnoseResponse(
            patterns: [p.finding(evidence: Array(unique.prefix(3)), confidence: min(0.9, 0.4 + 0.15 * Double(hits.count)))],
            kidMessage: "Great reading! Words with \(p.kidLabel) were a little tricky. Let's practice them together."
        )
    }
    let fallback = hardestPatternIn(pageText) ?? Patterns.all[0]
    return DiagnoseResponse(
        patterns: [fallback.finding(evidence: [], confidence: 0.2)],
        kidMessage: "Wow, you read every word! Let's see if Pip can keep up."
    )
}

/// Splits the page into sentences and plants one misreading on a word with the target pattern.
public func localPipPlan(pageIndex: Int, pageText: String, patterns: [PatternFinding]) -> PipPlan {
    var sentences: [PipSentence] = []
    var cursor = 0
    let re = try? NSRegularExpression(pattern: "[^.!?]+[.!?]+[\"'\u{201D}\u{2019}]*|[^.!?]+$")
    let parts = re?.matches(in: pageText, range: NSRange(pageText.startIndex..., in: pageText))
        .compactMap { Range($0.range, in: pageText).map { String(pageText[$0]) } } ?? [pageText]
    for part in parts {
        let n = tokenizeDisplay(part).count
        guard n > 0 else { continue }
        let t = part.trimmingCharacters(in: .whitespaces)
        sentences.append(PipSentence(index: sentences.count, text: t, spokenText: t, wordStart: cursor, wordEnd: cursor + n))
        cursor += n
    }

    var ids = patterns.map(\.id).filter(isPatternId)
    if let h = hardestPatternIn(pageText)?.id { ids.append(h) }
    ids += Patterns.all.map(\.id)
    var mistakes: [PlantedMistake] = []
    for id in ids {
        guard let w = wordsWithPattern(pageText, id).first(where: { $0.index > 0 && $0.index < cursor - 1 && $0.word.count >= 3 }),
              let si = sentences.firstIndex(where: { w.index >= $0.wordStart && w.index < $0.wordEnd }) else { continue }
        let misread = w.word.hasSuffix("ed") && w.word.count > 4
            ? String(w.word.dropLast(2))
            : w.word.replacingOccurrences(of: "[aeiou]+", with: "a", options: .regularExpression, range: w.word.range(of: "[aeiou]+", options: .regularExpression))
        guard misread != w.word else { continue }
        let bare = w.display.replacingOccurrences(of: "[^A-Za-z']", with: "", options: .regularExpression)
        if let r = sentences[si].spokenText.range(of: bare) {
            sentences[si].spokenText.replaceSubrange(r, with: misread)
        }
        mistakes.append(PlantedMistake(wordIndex: w.index, sentenceIndex: si, correct: w.word, misread: misread,
                                       speakAs: misread, patternId: id, reaction: "Oh! Thank you, teacher!"))
        break
    }
    return PipPlan(pageIndex: pageIndex, sentences: sentences, mistakes: mistakes)
}
