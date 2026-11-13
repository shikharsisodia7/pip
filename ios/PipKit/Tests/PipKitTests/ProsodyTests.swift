import XCTest
@testable import PipKit

// Port of lib/prosody/prosody.test.ts (the browser recorder tests are not
// applicable and are omitted), plus streaming tests for ProsodyAnalyzer and
// a cross-check against numbers produced by the TypeScript implementation.

private let SR = 44_100.0
private let leadInSeconds = 0.3
private let leadInAmplitude = 0.002 // low-level room noise ahead of the signal

// MARK: - Deterministic signals (identical to the TypeScript test helpers)

/// Deterministic PRNG (mulberry32) so noise-based tests are reproducible.
private struct Mulberry32 {
    private var a: UInt32

    init(seed: UInt32) { a = seed }

    mutating func next() -> Double {
        a = a &+ 0x6D2B_79F5
        var t = a
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

private func noise(_ seconds: Double, _ amplitude: Double, seed: UInt32, sampleRate: Double = SR) -> [Float] {
    var rand = Mulberry32(seed: seed)
    let count = Int((seconds * sampleRate).rounded())
    return (0..<count).map { _ in Float((rand.next() * 2 - 1) * amplitude) }
}

/// Phase-continuous tone. freq(t) and amp(t) take seconds. A little background
/// noise is mixed in so the signal is not unrealistically clean.
private func tone(
    _ seconds: Double,
    freq: (Double) -> Double,
    amp: (Double) -> Double,
    seed: UInt32 = 7,
    sampleRate: Double = SR
) -> [Float] {
    let bg = noise(seconds, leadInAmplitude, seed: seed, sampleRate: sampleRate)
    var out = [Float](repeating: 0, count: bg.count)
    var phase = 0.0
    for i in 0..<out.count {
        let t = Double(i) / sampleRate
        phase += (2 * Double.pi * freq(t)) / sampleRate
        out[i] = Float(amp(t) * sin(phase) + Double(bg[i]))
    }
    return out
}

/// Prepends the calibration lead-in so the adaptive noise floor is exercised.
private func withLeadIn(_ signal: [Float], seed: UInt32 = 1, sampleRate: Double = SR) -> [Float] {
    noise(leadInSeconds, leadInAmplitude, seed: seed, sampleRate: sampleRate) + signal
}

/// Triangle wave 0 -> 1 -> 0 over `period` seconds.
private func triangle(_ t: Double, _ period: Double) -> Double {
    let x = t.truncatingRemainder(dividingBy: period) / period
    return x < 0.5 ? x * 2 : 2 - x * 2
}

private func steadySignal(sampleRate: Double = SR) -> [Float] {
    withLeadIn(
        tone(3, freq: { _ in 200 }, amp: { t in 0.1 * (1 + 0.1 * sin(2 * Double.pi * 2 * t)) }, sampleRate: sampleRate),
        sampleRate: sampleRate
    )
}

/// 150 Hz -> 350 Hz -> 150 Hz over 3 s, with slow amplitude modulation.
private func sweepSignal(sampleRate: Double = SR) -> [Float] {
    withLeadIn(
        tone(
            3,
            freq: { t in 150 + 200 * triangle(t, 3) },
            amp: { t in 0.15 * (1 + 0.6 * sin(2 * Double.pi * 1.5 * t)) },
            sampleRate: sampleRate
        ),
        sampleRate: sampleRate
    )
}

/// Mildly intoned reading: +/- 2 semitones around 200 Hz.
private func mildSignal() -> [Float] {
    withLeadIn(
        tone(
            3,
            freq: { t in 200 * pow(2, (2 * sin(2 * Double.pi * 0.7 * t)) / 12) },
            amp: { t in 0.12 * (1 + 0.25 * sin(2 * Double.pi * 2.5 * t)) },
            seed: 11
        )
    )
}

/// 4 bursts per second: 150 ms tone, 100 ms gap, for 2 s.
private func burstSignal() -> [Float] {
    withLeadIn(tone(2, freq: { _ in 220 }, amp: { t in t.truncatingRemainder(dividingBy: 0.25) < 0.15 ? 0.15 : 0 }))
}

private let steady = steadySignal()
private let sweep = sweepSignal()

/// Feeds a signal through the analyzer at 44.1 kHz with the default 25 ms hop
/// (1103 samples), the same windows the TypeScript test harness uses.
private func analyzeSignal(_ signal: [Float], sampleRate: Double = SR) -> (stats: ProsodyStats, frames: [ProsodyFrame]) {
    let analyzer = ProsodyAnalyzer()
    let frames = analyzer.push(samples: signal, sampleRate: sampleRate)
    return (analyzer.finish(), frames)
}

private func assertNoNaN(_ stats: ProsodyStats, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(stats.pitchRangeSemitones.isFinite, "pitchRangeSemitones should be finite", file: file, line: line)
    XCTAssertTrue(stats.pitchSdSemitones.isFinite, "pitchSdSemitones should be finite", file: file, line: line)
    XCTAssertTrue(stats.loudnessSdDb.isFinite, "loudnessSdDb should be finite", file: file, line: line)
    XCTAssertTrue(stats.wordsPerSec.isFinite, "wordsPerSec should be finite", file: file, line: line)
}

private func stats(
    range: Double, sd: Double, loudness: Double, rate: Double, voiced: Int
) -> ProsodyStats {
    ProsodyStats(
        pitchRangeSemitones: range,
        pitchSdSemitones: sd,
        loudnessSdDb: loudness,
        wordsPerSec: rate,
        voicedFrames: .init(voiced)
    )
}

// A plausible reading-aloud baseline: moderate intonation, plenty of frames.
private let realisticBaseline = stats(range: 7, sd: 2.2, loudness: 4, rate: 3, voiced: 400)
// A monotone reading baseline: little pitch or loudness movement.
private let flatBaseline = stats(range: 2.5, sd: 0.8, loudness: 1.8, rate: 3, voiced: 400)

private let threshold = defaultExpressionThreshold

// MARK: - analyzeFrame

final class ProsodyAnalyzeFrameTests: XCTestCase {
    func testFindsA200HzToneWithHighClarity() {
        let detector = PitchDetector(frameSize: 2048)
        let sig = tone(0.1, freq: { _ in 200 }, amp: { _ in 0.2 })
        let a = ProsodyMath.analyzeFrame(Array(sig[0..<2048]), sampleRate: SR, detector: detector)
        XCTAssertGreaterThan(a.f0, 198)
        XCTAssertLessThan(a.f0, 202)
        XCTAssertGreaterThan(a.clarity, 0.95)
        XCTAssertGreaterThan(a.rms, 0.13)
        XCTAssertLessThan(a.rms, 0.15)
    }

    func testReturnsZerosForAWindowOfTheWrongLength() {
        let detector = PitchDetector(frameSize: 2048)
        let a = ProsodyMath.analyzeFrame([Float](repeating: 0, count: 100), sampleRate: SR, detector: detector)
        XCTAssertEqual(a, ProsodyFrameAnalysis(f0: 0, clarity: 0, rms: 0))
        let direct = detector.detect([Float](repeating: 0.1, count: 100), sampleRate: SR)
        XCTAssertEqual(direct.frequency, 0)
        XCTAssertEqual(direct.clarity, 0)
    }

    func testAllZeroWindowHasNoPitch() {
        let detector = PitchDetector()
        let result = detector.detect([Float](repeating: 0, count: 2048), sampleRate: SR)
        XCTAssertEqual(result.frequency, 0)
        XCTAssertEqual(result.clarity, 0)
    }
}

// MARK: - Analyzer with synthetic signals

final class ProsodyAnalyzerSignalTests: XCTestCase {
    func testSteadyToneHasAlmostNoPitchMovementAndFailsAgainstARealisticBaseline() {
        let (s, _) = analyzeSignal(steady)
        assertNoNaN(s)
        XCTAssertGreaterThan(s.voicedFrames, 100)
        XCTAssertLessThan(s.pitchSdSemitones, 0.5)
        XCTAssertLessThan(s.pitchRangeSemitones, 0.5)
        XCTAssertLessThan(s.loudnessSdDb, 1)

        let result = expressionScore(attempt: s, baseline: realisticBaseline, threshold: threshold)
        XCTAssertFalse(result.passed)
        XCTAssertLessThan(result.score, 0.3)
    }

    func testWideSlowSweepWithAmplitudeModulationPassesAgainstAFlatBaseline() {
        let (s, _) = analyzeSignal(sweep)
        assertNoNaN(s)
        XCTAssertGreaterThan(s.voicedFrames, 100)
        // The sweep spans 12 * log2(350 / 150), about 14.7 semitones.
        XCTAssertGreaterThan(s.pitchRangeSemitones, 10)
        XCTAssertGreaterThan(s.pitchSdSemitones, 3)
        XCTAssertGreaterThan(s.loudnessSdDb, 3)

        let result = expressionScore(attempt: s, baseline: flatBaseline, threshold: threshold)
        XCTAssertTrue(result.passed)
        XCTAssertGreaterThan(result.score, 2 * defaultExpressionThreshold)

        // It also clears a realistic baseline, while the steady tone does not.
        XCTAssertTrue(expressionScore(attempt: s, baseline: realisticBaseline, threshold: threshold).passed)
    }

    func testBaselineFromAMildlyIntonedSignalSeparatesTheTwoAttempts() {
        let baseline = analyzeSignal(mildSignal()).stats
        XCTAssertGreaterThanOrEqual(baseline.voicedFrames, 40)
        XCTAssertFalse(expressionScore(attempt: analyzeSignal(steady).stats, baseline: baseline, threshold: threshold).passed)
        XCTAssertTrue(expressionScore(attempt: analyzeSignal(sweep).stats, baseline: baseline, threshold: threshold).passed)
    }

    func testSilenceGivesZeroVoicedFramesAndAllZeroStats() {
        let (s, frames) = analyzeSignal([Float](repeating: 0, count: Int(SR) * 2))
        assertNoNaN(s)
        XCTAssertEqual(s, stats(range: 0, sd: 0, loudness: 0, rate: 0, voiced: 0))
        XCTAssertFalse(frames.isEmpty)
        XCTAssertTrue(frames.allSatisfy { $0.semitones == nil })
        let result = expressionScore(attempt: s, baseline: realisticBaseline, threshold: threshold)
        XCTAssertEqual(result.score, 0)
        XCTAssertFalse(result.passed)
    }

    func testLoudWhiteNoiseIsRejectedByTheClarityGate() {
        let loudNoise = noise(3, 0.2, seed: 99)

        // The clarity gate alone rejects the vast majority of noise frames. The
        // few that slip past report an f0 near sampleRate / frameSize (about
        // 22 Hz, an edge-of-window artifact), which the f0 range gate removes.
        let detector = PitchDetector(frameSize: 2048)
        let hop = Int((0.025 * SR).rounded())
        var total = 0
        var clear = 0
        var end = 2048
        while end <= loudNoise.count {
            let a = ProsodyMath.analyzeFrame(Array(loudNoise[(end - 2048)..<end]), sampleRate: SR, detector: detector)
            total += 1
            if a.clarity >= ProsodyConstants.minClarity {
                clear += 1
                XCTAssertLessThan(a.f0, ProsodyConstants.minF0Hz)
            }
            end += hop
        }
        XCTAssertLessThan(Double(clear) / Double(total), 0.08)

        let (s, _) = analyzeSignal(withLeadIn(loudNoise))
        assertNoNaN(s)
        XCTAssertEqual(s.voicedFrames, 0)
        XCTAssertFalse(expressionScore(attempt: s, baseline: nil, threshold: threshold).passed)
    }

    func testCapsTheNoiseFloorWhenSpeechStartsDuringCalibration() {
        // No lead-in: the calibration period measures the tone itself. Without
        // the cap the floor would sit above the tone and nothing would be voiced.
        let (s, _) = analyzeSignal(tone(2, freq: { _ in 200 }, amp: { _ in 0.15 }))
        XCTAssertGreaterThan(s.voicedFrames, 60)
    }

    func testAToneQuieterThanTheCalibratedNoiseFloorIsNotVoiced() {
        // Loud lead-in raises the floor; the following clean tone sits below it.
        let sig = noise(leadInSeconds, 0.006, seed: 5) + tone(1, freq: { _ in 200 }, amp: { _ in 0.003 })
        XCTAssertEqual(analyzeSignal(sig).stats.voicedFrames, 0)
    }

    func testEmitsLiveFramesWithNilSemitonesDuringCalibrationAndNumbersOnceVoiced() {
        let (_, frames) = analyzeSignal(sweep)
        let calibrating = frames.filter { $0.t < leadInSeconds }
        XCTAssertFalse(calibrating.isEmpty)
        XCTAssertTrue(calibrating.allSatisfy { $0.semitones == nil })
        let live = frames.filter { $0.semitones != nil }
        XCTAssertGreaterThan(live.count, 80)
        XCTAssertTrue(live.allSatisfy { ($0.semitones ?? Double.nan).isFinite && $0.rms.isFinite })
        let values = live.compactMap { $0.semitones }
        XCTAssertGreaterThan(values.max()! - values.min()!, 8)
    }

    func testEstimatesAnApproximateSyllableLikeRateFromVoicedBursts() {
        let s = analyzeSignal(burstSignal()).stats
        XCTAssertGreaterThan(s.wordsPerSec, 3)
        XCTAssertLessThan(s.wordsPerSec, 5.5)

        // A continuous tone has a single onset over its whole span.
        XCTAssertLessThan(analyzeSignal(steady).stats.wordsPerSec, 0.5)
    }

    func testFinishOnAnEmptyAnalyzerReturnsZeros() {
        let s = ProsodyAnalyzer().finish()
        assertNoNaN(s)
        XCTAssertEqual(s.voicedFrames, 0)
        XCTAssertEqual(ProsodyTracker().finish(), stats(range: 0, sd: 0, loudness: 0, rate: 0, voiced: 0))
    }
}

// MARK: - Streaming behavior

final class ProsodyAnalyzerStreamingTests: XCTestCase {
    private func pushInChunks(_ signal: [Float], chunk: Int, sampleRate: Double, into analyzer: ProsodyAnalyzer) -> [ProsodyFrame] {
        var frames: [ProsodyFrame] = []
        var start = 0
        while start < signal.count {
            let end = min(start + chunk, signal.count)
            frames += analyzer.push(samples: Array(signal[start..<end]), sampleRate: sampleRate)
            start = end
        }
        return frames
    }

    func testChunkSizeDoesNotChangeTheResultAt48kHz() {
        let rate = 48_000.0
        let signal = sweepSignal(sampleRate: rate)

        let whole = ProsodyAnalyzer()
        let wholeFrames = whole.push(samples: signal, sampleRate: rate)
        let wholeStats = whole.finish()
        XCTAssertGreaterThan(wholeStats.voicedFrames, 100)
        XCTAssertGreaterThan(wholeStats.pitchRangeSemitones, 10)

        for chunk in [4800, 1024, 1, 333, 2048, 10_000] {
            let analyzer = ProsodyAnalyzer()
            let frames = pushInChunks(signal, chunk: chunk, sampleRate: rate, into: analyzer)
            XCTAssertEqual(frames, wholeFrames, "chunk \(chunk)")
            XCTAssertEqual(analyzer.finish(), wholeStats, "chunk \(chunk)")
        }
    }

    func testFrameTimesAreWindowEndsInSecondsSinceTheFirstSample() {
        let rate = 48_000.0
        let analyzer = ProsodyAnalyzer()
        let frames = analyzer.push(samples: [Float](repeating: 0, count: 48_000), sampleRate: rate)
        // Hop is 0.025 * 48000 = 1200 samples; the first window ends at 2048.
        XCTAssertEqual(frames.count, (48_000 - 2048) / 1200 + 1)
        for (k, frame) in frames.enumerated() {
            XCTAssertEqual(frame.t, Double(2048 + k * 1200) / rate, accuracy: 1e-12)
        }
        XCTAssertTrue(analyzer.push(samples: [], sampleRate: rate).isEmpty)
        XCTAssertTrue(analyzer.push(samples: [0, 0], sampleRate: 0).isEmpty)
        XCTAssertTrue(analyzer.push(samples: [0, 0], sampleRate: .nan).isEmpty)
    }

    func testNoFrameUntilAFullWindowHasArrived() {
        let analyzer = ProsodyAnalyzer()
        XCTAssertTrue(analyzer.push(samples: [Float](repeating: 0.1, count: 2047), sampleRate: SR).isEmpty)
        XCTAssertEqual(analyzer.push(samples: [0.1], sampleRate: SR).count, 1)
    }

    func testResetClearsStateForReuse() {
        let analyzer = ProsodyAnalyzer()
        let first = analyzer.push(samples: sweep, sampleRate: SR)
        let firstStats = analyzer.finish()
        XCTAssertEqual(analyzer.finish(), firstStats, "finish() does not consume state")

        analyzer.reset()
        XCTAssertEqual(analyzer.finish().voicedFrames, 0)
        let second = analyzer.push(samples: sweep, sampleRate: SR)
        XCTAssertEqual(second, first)
        XCTAssertEqual(analyzer.finish(), firstStats)
    }

    func testSampleRateChangeKeepsTheTimeBaseContinuous() {
        let analyzer = ProsodyAnalyzer()
        let a = analyzer.push(samples: [Float](repeating: 0, count: 44_100), sampleRate: 44_100)
        let b = analyzer.push(samples: [Float](repeating: 0, count: 48_000), sampleRate: 48_000)
        XCTAssertFalse(a.isEmpty)
        XCTAssertFalse(b.isEmpty)
        XCTAssertEqual(b[0].t, 1.0 + 2048 / 48_000.0, accuracy: 1e-12)
        let times = (a + b).map(\.t)
        XCTAssertEqual(times, times.sorted())
    }
}

// MARK: - Track cleanup helpers

final class ProsodyHelperTests: XCTestCase {
    func testMedianFilterRemovesATwoFrameOctaveError() {
        let track = [0, 0.2, 0.1, 12, 12.1, 0.3, 0.2, 0.1]
        let filtered = ProsodyMath.medianFilter(track, window: 5)
        XCTAssertLessThan(filtered.max()!, 1)
    }

    func testDropsAnIsolatedJumpLargerThan10Semitones() {
        XCTAssertEqual(ProsodyMath.dropOctaveJumps([0, 0.5, 12, 0.4, 0.2]), [0, 0.5, 0.4, 0.2])
        XCTAssertEqual(ProsodyMath.dropOctaveJumps([12, 0.5, 0.4]), [0.5, 0.4])
    }

    func testPercentileInterpolatesAndHandlesEmptyInput() {
        XCTAssertEqual(ProsodyMath.percentile([], 50), 0)
        XCTAssertEqual(ProsodyMath.percentile([0, 10], 50), 5)
    }
}

// MARK: - expressionScore

final class ExpressionScoreTests: XCTestCase {
    private let expressive = stats(range: 10, sd: 3, loudness: 5, rate: 3, voiced: 120)
    private var monotone: ProsodyStats {
        var s = expressive
        s.pitchSdSemitones = 1.2
        s.loudnessSdDb = 2
        return s
    }

    func testFallsBackToAnAbsolutePitchSdRuleWhenTheBaselineIsNilOrTooShort() {
        var shortBaseline = realisticBaseline
        shortBaseline.voicedFrames = 39
        for baseline in [nil, shortBaseline] {
            let pass = expressionScore(attempt: expressive, baseline: baseline, threshold: threshold)
            XCTAssertTrue(pass.passed)
            XCTAssertEqual(pass.score, (3 / 2.5) * defaultExpressionThreshold, accuracy: 1e-6)

            let fail = expressionScore(attempt: monotone, baseline: baseline, threshold: threshold)
            XCTAssertFalse(fail.passed)
            XCTAssertLessThan(fail.score, defaultExpressionThreshold)
        }
        // Exactly 2.5 semitones lands on the default threshold and passes.
        var edgeAttempt = expressive
        edgeAttempt.pitchSdSemitones = 2.5
        let edge = expressionScore(attempt: edgeAttempt, baseline: nil, threshold: threshold)
        XCTAssertTrue(edge.passed)
        XCTAssertEqual(edge.score, defaultExpressionThreshold, accuracy: 1e-6)

        // The fallback pass rule is absolute and ignores the threshold.
        XCTAssertTrue(expressionScore(attempt: expressive, baseline: nil, threshold: 100).passed)
    }

    func testReturnsZeroAndFalseWhenTheAttemptHasFewerThan10VoicedFrames() {
        var short = expressive
        short.voicedFrames = 9
        for baseline in [realisticBaseline, nil] {
            let r = expressionScore(attempt: short, baseline: baseline, threshold: threshold)
            XCTAssertEqual(r.score, 0)
            XCTAssertFalse(r.passed)
        }
    }

    func testAppliesTheWeightedRatioWithDenominatorFloors() {
        var tinyBaseline = realisticBaseline
        tinyBaseline.pitchSdSemitones = 0.1
        tinyBaseline.loudnessSdDb = 0.2
        // Floors: 1.0 for pitch, 1.5 for loudness.
        let r = expressionScore(attempt: expressive, baseline: tinyBaseline, threshold: threshold)
        XCTAssertEqual(r.score, 0.6 * (3 / 1.0) + 0.4 * (5 / 1.5), accuracy: 1e-6)
    }

    func testNeverReturnsNaNForDegenerateInput() {
        var bad = expressive
        bad.pitchSdSemitones = .nan
        bad.loudnessSdDb = .infinity
        var badBaseline = realisticBaseline
        badBaseline.pitchSdSemitones = .nan
        let r = expressionScore(attempt: bad, baseline: badBaseline, threshold: threshold)
        XCTAssertTrue(r.score.isFinite)
        XCTAssertTrue(expressionScore(attempt: bad, baseline: nil, threshold: .nan).score.isFinite)
    }

    func testThresholdParameterControlsPassingAndNormalizesLikeTheWebSetter() {
        XCTAssertEqual(defaultExpressionThreshold, 1.25)
        // Score here is 0.6 * 2.2 / 2.2 + 0.4 * 4 / 4 = 1.0 against itself.
        let same = realisticBaseline
        XCTAssertFalse(expressionScore(attempt: same, baseline: realisticBaseline, threshold: defaultExpressionThreshold).passed)

        var t = defaultExpressionThreshold
        for _ in 0..<5 { t = normalizedExpressionThreshold(t - 0.05, current: t) }
        XCTAssertEqual(t, 1)
        XCTAssertTrue(expressionScore(attempt: same, baseline: realisticBaseline, threshold: t).passed)

        t = normalizedExpressionThreshold(t + 0.05, current: t)
        XCTAssertEqual(t, 1.05)
        XCTAssertFalse(expressionScore(attempt: same, baseline: realisticBaseline, threshold: t).passed)

        XCTAssertEqual(normalizedExpressionThreshold(2, current: t), 2)
        XCTAssertEqual(normalizedExpressionThreshold(.nan, current: 2), 2)
        XCTAssertEqual(normalizedExpressionThreshold(-1, current: 2), 0)

        // A non-finite threshold falls back to the default; a negative one acts as 0.
        XCTAssertFalse(expressionScore(attempt: same, baseline: realisticBaseline, threshold: .nan).passed)
        XCTAssertTrue(expressionScore(attempt: same, baseline: realisticBaseline, threshold: -1).passed)
    }
}

// MARK: - Cross-check against the TypeScript implementation

/// Reference values printed by running lib/prosody/analysis.ts (with pitchy
/// 4.1.0) on the same deterministic signals, at 44.1 kHz with a 1103-sample
/// hop. Regenerate with the throwaway script in the staging package
/// (crosscheck/crosscheck.ts) if the signals or the analysis change.
private enum TypeScriptReference {
    static let prng = [0.6011037519201636, 0.44829055899754167, 0.8524657934904099]

    static let steady = stats(
        range: 0.0017505977702070457, sd: 0.0005942006208200195,
        loudness: 0.6148256425422338, rate: 0.3388293867264932, voiced: 119
    )
    static let sweep = stats(
        range: 12.734171089017579, sd: 4.108475236491107,
        loudness: 4.065789545287099, rate: 0.3388293867264932, voiced: 119
    )
    static let mild = stats(
        range: 3.924378070299725, sd: 1.3886127880274957,
        loudness: 1.5280809794298662, rate: 0.3388293867264932, voiced: 119
    )
    static let bursts = stats(
        range: 0.000855297166409735, sd: 0.00036216938604096717,
        loudness: 0.016049616132877885, rate: 4.32236406851094, voiced: 40
    )
    static let framesPerRun = 131
    static let burstFrames = 91

    /// (f0, clarity, rms) of single windows.
    static let tone200 = (f0: 200.00576674682557, clarity: 0.9999360530602459, rms: 0.14169440719820542)
    static let sweepAt1300ms = (f0: 286.20868747085206, clarity: 0.9989700605070873, rms: 0.09309520594722952)
    static let mildAt2300ms = (f0: 211.87946761814138, clarity: 0.9991660445814254, rms: 0.09224894845433271)
    static let noiseAt1s = (f0: 21.714146573387772, clarity: 0.3838303462835029, rms: 0.11564906983921451)
    static let noiseClearFrames = 4
    static let noiseTotalFrames = 119
}

final class ProsodyCrossCheckTests: XCTestCase {
    private func assertClose(
        _ swift: ProsodyStats, _ ts: ProsodyStats, _ label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(swift.pitchSdSemitones, ts.pitchSdSemitones, accuracy: 0.15, "\(label) pitch SD", file: file, line: line)
        XCTAssertEqual(swift.pitchRangeSemitones, ts.pitchRangeSemitones, accuracy: 0.3, "\(label) pitch range", file: file, line: line)
        XCTAssertEqual(swift.loudnessSdDb, ts.loudnessSdDb, accuracy: 0.3, "\(label) loudness SD", file: file, line: line)
        XCTAssertEqual(swift.wordsPerSec, ts.wordsPerSec, accuracy: 0.05, "\(label) rate", file: file, line: line)
        XCTAssertEqual(Double(swift.voicedFrames), Double(ts.voicedFrames), accuracy: 2, "\(label) voiced frames", file: file, line: line)
    }

    func testPRNGMatchesMulberry32() {
        var r = Mulberry32(seed: 42)
        XCTAssertEqual([r.next(), r.next(), r.next()], TypeScriptReference.prng)
    }

    func testStatsMatchTheTypeScriptImplementation() {
        let steadyRun = analyzeSignal(steady)
        let sweepRun = analyzeSignal(sweep)
        let mildRun = analyzeSignal(mildSignal())
        let burstRun = analyzeSignal(burstSignal())

        XCTAssertEqual(steadyRun.frames.count, TypeScriptReference.framesPerRun)
        XCTAssertEqual(sweepRun.frames.count, TypeScriptReference.framesPerRun)
        XCTAssertEqual(burstRun.frames.count, TypeScriptReference.burstFrames)

        assertClose(steadyRun.stats, TypeScriptReference.steady, "steady")
        assertClose(sweepRun.stats, TypeScriptReference.sweep, "sweep")
        assertClose(mildRun.stats, TypeScriptReference.mild, "mild baseline")
        assertClose(burstRun.stats, TypeScriptReference.bursts, "bursts")

        // Printed so the report can show both implementations side by side.
        for (label, s) in [("steady", steadyRun.stats), ("sweep", sweepRun.stats), ("mild", mildRun.stats), ("bursts", burstRun.stats)] {
            print("CROSSCHECK \(label) range=\(s.pitchRangeSemitones) sd=\(s.pitchSdSemitones) loud=\(s.loudnessSdDb) rate=\(s.wordsPerSec) voiced=\(s.voicedFrames)")
        }
    }

    func testDetectorClarityMatchesPitchy() {
        let detector = PitchDetector()
        let mild = mildSignal()
        let loudNoise = noise(3, 0.2, seed: 99)
        let cases: [(String, [Float], Int, (f0: Double, clarity: Double, rms: Double))] = [
            ("tone200", tone(0.1, freq: { _ in 200 }, amp: { _ in 0.2 }), 0, TypeScriptReference.tone200),
            ("sweepAt1300ms", sweep, Int((1.3 * SR).rounded()), TypeScriptReference.sweepAt1300ms),
            ("mildAt2300ms", mild, Int((2.3 * SR).rounded()), TypeScriptReference.mildAt2300ms),
            ("noiseAt1s", loudNoise, Int((1.0 * SR).rounded()), TypeScriptReference.noiseAt1s),
        ]
        for (label, signal, start, ref) in cases {
            let a = ProsodyMath.analyzeFrame(Array(signal[start..<(start + 2048)]), sampleRate: SR, detector: detector)
            XCTAssertEqual(a.f0, ref.f0, accuracy: 1e-3, "\(label) f0")
            XCTAssertEqual(a.clarity, ref.clarity, accuracy: 1e-5, "\(label) clarity")
            XCTAssertEqual(a.rms, ref.rms, accuracy: 1e-9, "\(label) rms")
            print("CROSSCHECK detect \(label) f0=\(a.f0) clarity=\(a.clarity) rms=\(a.rms)")
        }

        let hop = Int((0.025 * SR).rounded())
        var total = 0
        var clear = 0
        var end = 2048
        while end <= loudNoise.count {
            let a = ProsodyMath.analyzeFrame(Array(loudNoise[(end - 2048)..<end]), sampleRate: SR, detector: detector)
            total += 1
            if a.clarity >= ProsodyConstants.minClarity { clear += 1 }
            end += hop
        }
        XCTAssertEqual(total, TypeScriptReference.noiseTotalFrames)
        XCTAssertEqual(Double(clear), Double(TypeScriptReference.noiseClearFrames), accuracy: 1)
        print("CROSSCHECK noise clear=\(clear)/\(total)")
    }
}
