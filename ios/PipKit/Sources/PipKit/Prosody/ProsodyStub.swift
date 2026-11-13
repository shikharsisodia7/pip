// STUB, deleted when the prosody port lands. Keep the signature.

import Foundation

/// How much more expressive the attempt is than the baseline (1.0 = same).
public func expressionScore(attempt: ProsodyStats, baseline: ProsodyStats?, threshold: Double) -> (score: Double, passed: Bool) {
    guard let b = baseline, b.pitchSdSemitones > 0 else {
        let s = attempt.pitchSdSemitones > 2 ? 1.5 : 1.0
        return (s, s >= threshold)
    }
    let s = attempt.pitchSdSemitones / b.pitchSdSemitones
    return (s, s >= threshold)
}
