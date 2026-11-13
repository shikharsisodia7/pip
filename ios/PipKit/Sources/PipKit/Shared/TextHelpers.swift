// FROZEN shared helper. Port of lib/text.ts with identical behavior.
// tokenizeDisplay defines the page word index used everywhere (karaoke,
// alignment, PipSentence ranges, PlantedMistake.wordIndex).

import Foundation

private let numberWords: [String: String] = [
    "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four", "5": "five",
    "6": "six", "7": "seven", "8": "eight", "9": "nine", "10": "ten",
    "11": "eleven", "12": "twelve", "13": "thirteen", "14": "fourteen",
    "15": "fifteen", "16": "sixteen", "17": "seventeen", "18": "eighteen",
    "19": "nineteen", "20": "twenty",
]

private func regexReplace(_ s: String, _ pattern: String, _ template: String) -> String {
    s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
}

/// Lowercase, straighten quotes, strip punctuation at the edges, spell out 0-20.
public func normalizeToken(_ s: String) -> String {
    var t = s.lowercased()
    t = regexReplace(t, "[\u{2018}\u{2019}\u{02BC}`]", "'")
    t = regexReplace(t, "[\u{2010}\u{2011}\u{2012}]", "-")
    t = regexReplace(t, "[^a-z0-9'-]", "")
    t = regexReplace(t, "^['-]+|['-]+$", "")
    return numberWords[t] ?? t
}

public struct Token: Sendable, Equatable {
    /// The word as printed on the page, punctuation included ("drum.").
    public var display: String
    /// normalizeToken(display), never empty.
    public var norm: String
    public init(display: String, norm: String) { self.display = display; self.norm = norm }
}

/// Split text into page words. Index i here is "page word index i" everywhere in the app.
public func tokenizeDisplay(_ text: String) -> [Token] {
    let spaced = regexReplace(text, "\\s*([\u{2013}\u{2014}]|--)\\s*", "$1 ")
    return spaced
        .split(whereSeparator: { $0.isWhitespace })
        .map { Token(display: String($0), norm: normalizeToken(String($0))) }
        .filter { !$0.norm.isEmpty }
}

/// Normalized page words, same indexes as tokenizeDisplay.
public func tokenize(_ text: String) -> [String] {
    tokenizeDisplay(text).map(\.norm)
}

/// Levenshtein distance.
public func editDistance(_ a: String, _ b: String) -> Int {
    if a == b { return 0 }
    let x = Array(a), y = Array(b)
    if x.isEmpty { return y.count }
    if y.isEmpty { return x.count }
    var prev = Array(0...y.count)
    for i in 1...x.count {
        var cur = [i] + Array(repeating: 0, count: y.count)
        for j in 1...y.count {
            let cost = x[i - 1] == y[j - 1] ? 0 : 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        }
        prev = cur
    }
    return prev[y.count]
}

/// Same spoken word? Exact after normalization (apostrophes ignored), or edit
/// distance 1 for words of 5+ characters. Forgives speech-recognition spelling
/// noise on long words but keeps real short-word substitutions as errors.
public func fuzzyEqual(_ a: String, _ b: String) -> Bool {
    let na = normalizeToken(a).replacingOccurrences(of: "'", with: "")
    let nb = normalizeToken(b).replacingOccurrences(of: "'", with: "")
    if na.isEmpty || nb.isEmpty { return false }
    if na == nb { return true }
    return min(na.count, nb.count) >= 5 && editDistance(na, nb) <= 1
}
