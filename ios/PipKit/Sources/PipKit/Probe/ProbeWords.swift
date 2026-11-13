// STUB, replaced by the probe card. Keep the signature.

import Foundation

public enum ProbeKind: String, Sendable { case pre, post }

/// Five isolated words for the pre or post probe. Post words are different
/// words that share the diagnosed pattern.
public func pickProbeWords(kind: ProbeKind, patterns: [PatternFinding]) -> [ProbeItem] {
    let pre = ["looked", "jumped", "played", "night", "rain"]
    let post = ["called", "rolled", "smiled", "light", "train"]
    let words = kind == .pre ? pre : post
    return words.map { ProbeItem(word: $0, patternId: patternsForWord($0).first?.id ?? "ed") }
}
