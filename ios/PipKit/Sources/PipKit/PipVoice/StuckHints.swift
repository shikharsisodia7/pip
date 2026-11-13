// Help for a word the child is stuck on: the word split into readable chunks,
// with the tricky chunk marked, plus a short line for Pip to say. Pure logic,
// no network, so it works offline and in mock mode.

import Foundation

public struct StuckHint: Sendable, Equatable {
    /// The word as normalized for matching.
    public var word: String
    /// The word split into reading chunks, e.g. ["l", "oo", "k", "ed"].
    public var chunks: [String]
    /// Index into chunks of the tricky part, when the word has a known pattern.
    public var trickyIndex: Int?
    /// Kid label of the word's hardest pattern, e.g. "the 'oo' sound".
    public var patternLabel: String?
    /// Short line for the hint card.
    public var title: String
    /// Line for Pip to say aloud (may contain eleven_v3 audio tags).
    public var spoken: String
}

/// Letter teams read as one sound, longest first so "ough" wins over "ou".
private let letterTeams: [String] = [
    "ough", "augh", "eigh", "tch", "igh", "dge",
    "ck", "sh", "ch", "th", "wh", "ph", "ng", "qu", "kn", "wr",
    "ee", "ea", "ai", "ay", "oa", "oo", "ou", "ow", "oi", "oy", "aw", "ew", "ie", "ue",
    "ar", "or", "er", "ir", "ur",
]

/// The letter team or ending that best shows each pattern id.
private let patternChunk: [String: [String]] = [
    "ough": ["ough"], "igh": ["igh"], "ed": ["ed"], "ou": ["ou"], "ea": ["ea"],
    "er": ["er", "ir", "ur"], "ow": ["ow"], "ai": ["ai", "ay"], "oa": ["oa"], "oo": ["oo"],
    "oi": ["oi", "oy"], "ar": ["ar"], "or": ["or"], "wh": ["wh"], "ee": ["ee"],
    "th": ["th"], "sh": ["sh"], "ch": ["ch"],
]

/// Splits a word into reading chunks: letter teams stay together, an "-ed"
/// ending is its own chunk, everything else is one letter per chunk.
public func readingChunks(_ word: String) -> [String] {
    let w = normalizeToken(word)
    guard !w.isEmpty else { return [] }
    var body = w
    var ending: String?
    if let ed = getPattern("ed"), ed.test(w) {
        body = String(w.dropLast(2))
        ending = "ed"
    }
    var chunks: [String] = []
    var i = body.startIndex
    while i < body.endIndex {
        let rest = body[i...]
        if let team = letterTeams.first(where: { rest.hasPrefix($0) }) {
            chunks.append(team)
            i = body.index(i, offsetBy: team.count)
        } else {
            chunks.append(String(body[i]))
            i = body.index(after: i)
        }
    }
    if let ending { chunks.append(ending) }
    return chunks
}

/// Builds the hint for one word. Never fails: a word with no known pattern
/// still gets chunks and a gentle line.
public func stuckHint(for word: String) -> StuckHint {
    let norm = normalizeToken(word)
    let chunks = readingChunks(norm)
    let pattern = patternsForWord(norm).first
    var tricky: Int?
    if let pattern, let wanted = patternChunk[pattern.id] {
        tricky = chunks.lastIndex(where: { wanted.contains($0) })
    }
    let silentE = pattern?.id == "silent-e"
    if silentE, chunks.count >= 2 { tricky = chunks.count - 1 }

    let title: String
    let spoken: String
    if let pattern {
        let label = pattern.kidLabel
        if silentE {
            title = "The e at the end is quiet. It helps the other vowel say its name."
        } else {
            title = "This word has \(label)."
        }
        let example = pattern.example == norm ? "" : " Like in \(pattern.example)."
        spoken = "[warm] Let's try it together. This word has \(label).\(example) Listen... \(norm). \(norm)!"
    } else {
        title = "Try it in little parts."
        spoken = "[warm] Let's try it together. Listen... \(norm). \(norm)!"
    }
    return StuckHint(word: norm, chunks: chunks, trickyIndex: tricky, patternLabel: pattern?.kidLabel,
                     title: title, spoken: spoken)
}

/// Decides when the child is stuck: the transcript has not grown for
/// `stallSeconds`, the child has started reading, and Pip has helps left.
public struct StallDetector: Sendable {
    public var stallSeconds: Double
    public var maxHelpsPerPage: Int
    public private(set) var lastSignature: String = ""
    private(set) var lastChange: Double = 0
    public private(set) var helped: [Int] = []

    public init(stallSeconds: Double = 3, maxHelpsPerPage: Int = 3) {
        self.stallSeconds = stallSeconds
        self.maxHelpsPerPage = maxHelpsPerPage
    }

    /// Feed the latest listener state. Returns the word index to help with, or nil.
    /// `signature` changes whenever anything new is heard; `currentIndex` is the next word to read.
    public mutating func update(signature: String, wordsHeard: Int, currentIndex: Int?, now: Double) -> Int? {
        if signature != lastSignature {
            lastSignature = signature
            lastChange = now
            return nil
        }
        guard wordsHeard > 0, let index = currentIndex,
              now - lastChange >= stallSeconds,
              helped.count < maxHelpsPerPage,
              !helped.contains(index) else { return nil }
        helped.append(index)
        return index
    }

    public mutating func reset() {
        lastSignature = ""
        lastChange = 0
        helped = []
    }
}
