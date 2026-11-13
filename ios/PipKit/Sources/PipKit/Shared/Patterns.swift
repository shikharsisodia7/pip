// FROZEN shared helper. Port of lib/patterns.ts with identical behavior.
// PatternFinding.id must always be one of these ids.

import Foundation

public struct PhonicsPattern: Sendable {
    public let id: String
    public let kidLabel: String
    public let teacherLabel: String
    /// 1 (easy) to 5 (hard).
    public let difficulty: Int
    /// A word that shows the pattern.
    public let example: String
    private let tester: @Sendable (String) -> Bool

    public init(id: String, kidLabel: String, teacherLabel: String, difficulty: Int, example: String,
                test: @escaping @Sendable (String) -> Bool) {
        self.id = id; self.kidLabel = kidLabel; self.teacherLabel = teacherLabel
        self.difficulty = difficulty; self.example = example; self.tester = test
    }

    public func test(_ word: String) -> Bool { tester(word) }
}

private let edExceptions: Set<String> = [
    "need", "feed", "seed", "weed", "deed", "heed", "reed", "speed", "bleed", "breed", "greed", "steed",
    "bed", "red", "fed", "led", "wed", "shed", "sled", "bred", "sped", "fled", "shred",
    "hundred", "sacred", "naked", "wicked", "indeed", "proceed", "exceed", "succeed",
]
private let silentEExceptions: Set<String> = [
    "have", "give", "live", "love", "come", "some", "done", "gone", "none", "one", "once",
    "were", "there", "where", "here", "move", "lose", "whose", "above", "glove", "dove",
]
private let ouExceptions: Set<String> = [
    "you", "your", "you're", "yours", "could", "would", "should", "four", "pour", "touch", "young", "soul",
]

private func matches(_ s: String, _ pattern: String) -> Bool {
    s.range(of: pattern, options: .regularExpression) != nil
}

private func has(_ pattern: String) -> @Sendable (String) -> Bool {
    { word in matches(normalizeToken(word), pattern) }
}

public enum Patterns {
    /// Ordered hardest first.
    public static let all: [PhonicsPattern] = [
        PhonicsPattern(id: "ough", kidLabel: "the 'ough' sound", teacherLabel: "vowel team: ough", difficulty: 5, example: "thought", test: has("ough")),
        PhonicsPattern(id: "igh", kidLabel: "the 'igh' sound", teacherLabel: "vowel team: igh (-ight)", difficulty: 4, example: "night", test: has("igh")),
        PhonicsPattern(id: "ed", kidLabel: "words ending in '-ed'", teacherLabel: "inflectional ending: -ed", difficulty: 3, example: "jumped", test: { w in
            let n = normalizeToken(w)
            return n.count >= 4 && n.hasSuffix("ed") && !edExceptions.contains(n)
        }),
        PhonicsPattern(id: "silent-e", kidLabel: "the sneaky silent e", teacherLabel: "VCe (silent e)", difficulty: 3, example: "smile", test: { w in
            let n = normalizeToken(w)
            return !silentEExceptions.contains(n) && matches(n, "(^|[^aeiou])[aeiou][bcdfgklmnprstvz]e$")
        }),
        PhonicsPattern(id: "ou", kidLabel: "the 'ou' sound", teacherLabel: "vowel team: ou", difficulty: 3, example: "loud", test: { w in
            let n = normalizeToken(w)
            return matches(n, "ou") && !matches(n, "ough") && !ouExceptions.contains(n)
        }),
        PhonicsPattern(id: "ea", kidLabel: "the 'ea' sound", teacherLabel: "vowel team: ea", difficulty: 3, example: "dream", test: has("ea")),
        PhonicsPattern(id: "er", kidLabel: "the 'er' sound", teacherLabel: "r-controlled vowel: er / ir / ur", difficulty: 3, example: "bird", test: has("er|ir|ur")),
        PhonicsPattern(id: "ow", kidLabel: "the 'ow' sound", teacherLabel: "vowel team: ow", difficulty: 3, example: "owl", test: has("ow")),
        PhonicsPattern(id: "ai", kidLabel: "the 'ai' sound", teacherLabel: "vowel team: ai / ay", difficulty: 2, example: "rain", test: has("ai|ay")),
        PhonicsPattern(id: "oa", kidLabel: "the 'oa' sound", teacherLabel: "vowel team: oa", difficulty: 2, example: "boat", test: has("oa")),
        PhonicsPattern(id: "oo", kidLabel: "the 'oo' sound", teacherLabel: "vowel team: oo", difficulty: 2, example: "moon", test: has("oo")),
        PhonicsPattern(id: "oi", kidLabel: "the 'oi' sound", teacherLabel: "diphthong: oi / oy", difficulty: 2, example: "boy", test: has("oi|oy")),
        PhonicsPattern(id: "ar", kidLabel: "the 'ar' sound", teacherLabel: "r-controlled vowel: ar", difficulty: 2, example: "star", test: has("ar")),
        PhonicsPattern(id: "or", kidLabel: "the 'or' sound", teacherLabel: "r-controlled vowel: or", difficulty: 2, example: "storm", test: has("or")),
        PhonicsPattern(id: "wh", kidLabel: "the 'wh' sound", teacherLabel: "digraph: wh", difficulty: 2, example: "whisper", test: has("^wh")),
        PhonicsPattern(id: "ee", kidLabel: "the 'ee' sound", teacherLabel: "vowel team: ee", difficulty: 1, example: "tree", test: has("ee")),
        PhonicsPattern(id: "th", kidLabel: "the 'th' sound", teacherLabel: "digraph: th", difficulty: 1, example: "think", test: has("th")),
        PhonicsPattern(id: "sh", kidLabel: "the 'sh' sound", teacherLabel: "digraph: sh", difficulty: 1, example: "ship", test: has("sh")),
        PhonicsPattern(id: "ch", kidLabel: "the 'ch' sound", teacherLabel: "digraph: ch", difficulty: 1, example: "chin", test: has("ch")),
    ]
}

public func getPattern(_ id: String) -> PhonicsPattern? {
    Patterns.all.first { $0.id == id }
}

public func isPatternId(_ id: String) -> Bool {
    getPattern(id) != nil
}

/// Every pattern the word contains, hardest first.
public func patternsForWord(_ word: String) -> [PhonicsPattern] {
    Patterns.all.filter { $0.test(word) }
}

public struct PatternWord: Sendable, Equatable {
    /// Page word index (same indexes as tokenizeDisplay).
    public var index: Int
    /// Normalized word.
    public var word: String
    /// Word as printed.
    public var display: String
}

/// Page words containing the pattern, with their page word indexes.
public func wordsWithPattern(_ text: String, _ id: String) -> [PatternWord] {
    guard let p = getPattern(id) else { return [] }
    return tokenizeDisplay(text).enumerated()
        .map { PatternWord(index: $0.offset, word: $0.element.norm, display: $0.element.display) }
        .filter { p.test($0.word) }
}

/// The hardest taxonomy pattern that appears in the text, if any.
public func hardestPatternIn(_ text: String) -> PhonicsPattern? {
    let words = tokenize(text)
    return Patterns.all.first { p in words.contains { p.test($0) } }
}

public extension PhonicsPattern {
    /// A PatternFinding with taxonomy labels.
    func finding(evidence: [String] = [], confidence: Double = 0.3) -> PatternFinding {
        PatternFinding(id: id, kidLabel: kidLabel, teacherLabel: teacherLabel, evidenceWords: evidence, confidence: confidence)
    }
}
