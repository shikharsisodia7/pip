import Foundation

/// Default pass threshold for `expressionScore` with a usable baseline.
public let defaultExpressionThreshold = 1.25

/// Constants for expression scoring. Values match lib/prosody/score.ts.
public enum ExpressionScoreConstants {
    /// Denominator floors so a very flat baseline cannot inflate the ratio.
    public static let baselinePitchSdFloor = 1.0
    public static let baselineLoudnessSdFloor = 1.5

    public static let pitchWeight = 0.6
    public static let loudnessWeight = 0.4

    /// Below this many voiced frames the baseline is not trusted.
    public static let minBaselineVoicedFrames = 40
    /// Below this many voiced frames the attempt is treated as no attempt.
    public static let minAttemptVoicedFrames = 10

    /// Absolute fallback: pitch SD (semitones) that counts as expressive.
    public static let fallbackPitchSd = 2.5
}

/// Scores an expressive attempt relative to the speaker's reading baseline.
/// Port of `expressionScore` in lib/prosody/score.ts, with the threshold
/// passed in instead of read from module state.
///
/// With a usable baseline:
///
///     score = 0.6 * attemptPitchSd / max(baselinePitchSd, 1.0)
///           + 0.4 * attemptLoudnessSd / max(baselineLoudnessSd, 1.5)
///     passed = score >= threshold
///
/// Without one (nil, or fewer than 40 voiced frames), an absolute fallback:
///
///     score = (attemptPitchSd / 2.5) * defaultExpressionThreshold
///     passed = attemptPitchSd >= 2.5
///
/// The mapping puts a pitch SD of 2.5 semitones exactly at the default
/// threshold, so the score stays on the same scale for the meter UI. The
/// fallback pass rule is absolute and does not move with `threshold`.
///
/// An attempt with fewer than 10 voiced frames scores 0 and does not pass.
/// Non-finite statistics are treated as 0, so the score is always finite.
/// A non-finite `threshold` falls back to `defaultExpressionThreshold`, and a
/// negative one is treated as 0, matching what the web setter would store.
public func expressionScore(attempt: ProsodyStats, baseline: ProsodyStats?, threshold: Double) -> (score: Double, passed: Bool) {
    typealias C = ExpressionScoreConstants

    guard Double(attempt.voicedFrames) >= Double(C.minAttemptVoicedFrames) else {
        return (0, false)
    }
    let pitchSd = max(0, finiteOrZero(attempt.pitchSdSemitones))
    let loudnessSd = max(0, finiteOrZero(attempt.loudnessSdDb))

    guard let baseline, Double(baseline.voicedFrames) >= Double(C.minBaselineVoicedFrames) else {
        let score = finiteOrZero((pitchSd / C.fallbackPitchSd) * defaultExpressionThreshold)
        return (score, pitchSd >= C.fallbackPitchSd)
    }

    let pitchDen = max(finiteOrZero(baseline.pitchSdSemitones), C.baselinePitchSdFloor)
    let loudDen = max(finiteOrZero(baseline.loudnessSdDb), C.baselineLoudnessSdFloor)
    let score = finiteOrZero(C.pitchWeight * (pitchSd / pitchDen) + C.loudnessWeight * (loudnessSd / loudDen))
    let effectiveThreshold = threshold.isFinite ? max(0, threshold) : defaultExpressionThreshold
    return (score, score >= effectiveThreshold)
}

/// Normalizes a threshold the way the web `setThreshold` does: rounds to
/// three decimals and clamps at 0. A non-finite value returns `current`
/// unchanged. Use `normalizedExpressionThreshold(current + delta, current: current)`
/// for the web `nudgeThreshold` behavior.
public func normalizedExpressionThreshold(_ value: Double, current: Double = defaultExpressionThreshold) -> Double {
    guard value.isFinite else { return current }
    // Math.round rounds half toward positive infinity.
    return max(0, (value * 1000 + 0.5).rounded(.down) / 1000)
}

private func finiteOrZero(_ x: Double) -> Double {
    x.isFinite ? x : 0
}
