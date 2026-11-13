import Foundation

private enum AlignmentStep {
    case word(WordStatus, spokenCount: Int)
    case insertion
}

private func isFalseStart(_ attempt: String, expected: String) -> Bool {
    let prefix = attempt.replacingOccurrences(of: "'", with: "")
    let word = expected.replacingOccurrences(of: "'", with: "")
    return !prefix.isEmpty && prefix.count < word.count && word.hasPrefix(prefix)
}

/// Needleman-Wunsch alignment with one-word retries and repeated correct words.
/// Returns one word per tokenizeDisplay index, including unread trailing omissions.
public func alignWords(expectedText: String, transcript: Transcript) -> AlignmentResult {
    let expected = tokenizeDisplay(expectedText)
    let spoken = transcript.words.map {
        TimedWord(text: normalizeToken($0.text), start: $0.start, end: $0.end)
    }.filter { !$0.text.isEmpty }
    let matches = expected.map { word in spoken.map { fuzzyEqual(word.norm, $0.text) } }
    var costs = Array(repeating: Array(repeating: 0, count: spoken.count + 1), count: expected.count + 1)
    var steps = Array(
        repeating: Array<AlignmentStep?>(repeating: nil, count: spoken.count + 1),
        count: expected.count + 1
    )

    // Work backwards so backtracing follows the page in reading order.
    for i in stride(from: expected.count, through: 0, by: -1) {
        for j in stride(from: spoken.count, through: 0, by: -1) {
            if i == expected.count && j == spoken.count { continue }
            var bestCost = Int.max
            var bestStep: AlignmentStep?
            func consider(_ cost: Int, _ step: AlignmentStep, preferTie: Bool = false) {
                if cost < bestCost || (preferTie && cost == bestCost) {
                    bestCost = cost
                    bestStep = step
                }
            }

            if i < expected.count && j < spoken.count {
                consider(costs[i + 1][j + 1] + (matches[i][j] ? 0 : 1),
                         .word(matches[i][j] ? .correct : .substitution, spokenCount: 1))

                // Repeats can cover one page word, but must not consume a
                // separate occurrence on the page when doing so costs more.
                func considerRun(firstMatch: Int, corrected: Bool) {
                    for end in (firstMatch + 1)...spoken.count {
                        consider(costs[i + 1][end] + (corrected ? 1 : 0),
                                 .word(corrected ? .selfCorrected : .correct, spokenCount: end - j),
                                 preferTie: corrected && matches[i][j]
                                    && isFalseStart(spoken[j].text, expected: expected[i].norm))
                        if end == spoken.count || !matches[i][end]
                            || isFalseStart(spoken[end - 1].text, expected: expected[i].norm) { break }
                    }
                }

                if matches[i][j] { considerRun(firstMatch: j, corrected: false) }
                if j + 1 < spoken.count && matches[i][j + 1]
                    && (!matches[i][j] || isFalseStart(spoken[j].text, expected: expected[i].norm)) {
                    // An immediate retry costs as much as an insertion,
                    // but the corrected page word scores as correct.
                    considerRun(firstMatch: j + 1, corrected: true)
                }
            }
            if i < expected.count {
                consider(costs[i + 1][j] + 1, .word(.omission, spokenCount: 0))
            }
            if j < spoken.count {
                consider(costs[i][j + 1] + 1, .insertion)
            }
            costs[i][j] = bestCost
            steps[i][j] = bestStep
        }
    }

    var result = AlignmentResult(words: [], insertions: [])
    var i = 0
    var j = 0
    while i < expected.count || j < spoken.count {
        switch steps[i][j]! {
        case .insertion:
            // -1 denotes speech before the first page word.
            result.insertions.append(Insertion(afterIndex: i - 1, said: spoken[j].text))
            j += 1
        case let .word(status, spokenCount):
            var word = AlignedWord(index: i, expected: expected[i].norm, status: status)
            if status != .omission {
                let matchedIndex = status == .selfCorrected ? j + 1 : j
                let matched = spoken[matchedIndex]
                word.start = matched.start
                word.end = matched.end
                if status == .substitution || status == .selfCorrected {
                    word.said = spoken[j].text
                }
                if matchedIndex > 0 {
                    let gap = matched.start - spoken[matchedIndex - 1].end
                    if gap > 0.8 + 1e-9 { word.hesitationBeforeSec = gap }
                }
            }
            result.words.append(word)
            i += 1
            j += spokenCount
        }
    }
    return result
}
