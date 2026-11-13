/// Scores page words over the time covered by their valid timestamps.
public func computeMetrics(_ alignment: AlignmentResult) -> ReadingMetrics {
    let words = alignment.words
    let total = words.count
    let correct = words.filter { $0.status == .correct || $0.status == .selfCorrected }.count
    var first = Double.infinity
    var last = -Double.infinity
    for word in words {
        if let start = word.start, let end = word.end,
           start.isFinite, end.isFinite, end >= start {
            first = min(first, start)
            last = max(last, end)
        }
    }
    let duration = max(0, last - first)
    return ReadingMetrics(
        wcpm: duration > 0 ? (Double(correct) / (duration / 60)).rounded() : 0,
        accuracyPct: total > 0 ? (100 * Double(correct) / Double(total)).rounded() : 0,
        wordsCorrect: correct,
        wordsTotal: total,
        durationSec: (duration * 100).rounded() / 100,
        hesitations: words.filter { ($0.hesitationBeforeSec ?? 0) > 0.8 + 1e-9 }.count,
        selfCorrections: words.filter { $0.status == .selfCorrected }.count
    )
}
