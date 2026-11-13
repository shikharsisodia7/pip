import Foundation

/// Constants for prosody analysis. Values match lib/prosody/analysis.ts.
public enum ProsodyConstants {
    /// Analysis window length in samples. Matches the web AnalyserNode fftSize.
    public static let frameSize = 2048
    /// Time between analysis windows, in seconds. Matches the web poll interval.
    public static let hopSeconds = 0.025

    /// Voicing gate: minimum pitch clarity for a frame to count as voiced.
    public static let minClarity = 0.9
    /// Voicing gate: plausible f0 range for a child or adult speaking voice, Hz.
    public static let minF0Hz = 80.0
    public static let maxF0Hz = 600.0

    /// Length of the noise floor calibration period at the start of a recording.
    public static let calibrationSeconds = 0.3
    /// Noise floor = clamp(noiseFloorFactor x median calibration RMS).
    public static let noiseFloorFactor = 2.5
    public static let noiseFloorMin = 1e-4
    /// Upper bound on the noise floor. If the speaker starts talking during the
    /// calibration period, the measured noise is actually speech, and an
    /// unbounded floor would reject the rest of the recording.
    public static let noiseFloorMax = 0.02

    /// Median filter window applied to the voiced semitone track.
    public static let medianWindow = 5
    /// A voiced frame further than this from its neighbors is treated as an octave error.
    public static let maxJumpSemitones = 10.0
    /// Unvoiced gap that separates two voiced segments for the speaking rate estimate.
    public static let segmentGapSeconds = 0.08
}

/// Streaming prosody analysis: per-frame pitch and loudness from microphone
/// audio, live display frames, and summary statistics for a recording.
///
/// This is a port of lib/prosody/analysis.ts. Feed it mono samples at the
/// hardware rate in chunks of any length. The analyzer keeps the most recent
/// `frameSize` samples in a ring buffer and analyzes one window every hop
/// (`hopSeconds` rounded to whole samples). A frame's `t` is the time of the
/// window's last sample, in seconds since the first sample pushed.
///
/// Live frames use only information available so far: they report nil
/// semitones until the noise floor calibration (the first 300 ms of frames)
/// completes, and semitones are relative to a running median of voiced f0.
/// `finish()` re-evaluates every frame with the calibrated noise floor and
/// the speaker's overall median f0.
///
/// All methods are serialized by an internal lock, so an instance may be fed
/// from an audio thread and finished from another thread.
public final class ProsodyAnalyzer: @unchecked Sendable {
    private let lock = NSLock()
    private let frameSize: Int
    private let hopSeconds: Double
    private let detector: PitchDetector

    private var tracker = ProsodyTracker()
    private var ring: [Float]
    private var ringWriteIndex = 0

    private var currentSampleRate: Double?
    private var hopSamples = 1
    /// Seconds of audio received at earlier sample rates.
    private var timeOffset = 0.0
    /// Samples received at the current sample rate.
    private var segmentSampleCount = 0
    /// Segment sample count at which the next window is analyzed.
    private var nextWindowEnd: Int

    /// Creates an analyzer.
    /// - Parameters:
    ///   - frameSize: Analysis window length in samples.
    ///   - hopSeconds: Time between analysis windows, in seconds.
    public init(frameSize: Int = ProsodyConstants.frameSize, hopSeconds: Double = ProsodyConstants.hopSeconds) {
        precondition(frameSize >= 1, "frameSize must be at least one")
        self.frameSize = frameSize
        self.hopSeconds = hopSeconds
        self.detector = PitchDetector(frameSize: frameSize)
        self.ring = [Float](repeating: 0, count: frameSize)
        self.nextWindowEnd = frameSize
    }

    /// Adds a chunk of mono samples and returns a live frame for every
    /// analysis window completed by this chunk (possibly none).
    ///
    /// A change of `sampleRate` between calls starts a new window sequence at
    /// the new rate; the time base continues from the audio already received.
    /// Empty chunks and non-positive or non-finite rates are ignored.
    public func push(samples: [Float], sampleRate: Double) -> [ProsodyFrame] {
        lock.lock()
        defer { lock.unlock() }

        guard sampleRate.isFinite, sampleRate > 0, !samples.isEmpty else { return [] }
        if sampleRate != currentSampleRate {
            beginSegment(sampleRate: sampleRate)
        }

        var frames: [ProsodyFrame] = []
        var index = 0
        while index < samples.count {
            let take = Swift.min(nextWindowEnd - segmentSampleCount, samples.count - index)
            appendToRing(samples, from: index, count: take)
            index += take
            segmentSampleCount += take

            if segmentSampleCount == nextWindowEnd {
                let t = timeOffset + Double(nextWindowEnd) / sampleRate
                let analysis = ProsodyMath.analyzeFrame(currentWindow(), sampleRate: sampleRate, detector: detector)
                frames.append(tracker.push(t: t, analysis))
                nextWindowEnd += hopSamples
            }
        }
        return frames
    }

    /// Summary statistics over everything pushed since the last reset. Does
    /// not clear state; call `reset()` before reusing the analyzer.
    public func finish() -> ProsodyStats {
        lock.lock()
        defer { lock.unlock() }
        return tracker.finish()
    }

    /// Clears all state so the analyzer can be reused for a new recording.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        tracker = ProsodyTracker()
        for i in ring.indices { ring[i] = 0 }
        ringWriteIndex = 0
        currentSampleRate = nil
        hopSamples = 1
        timeOffset = 0
        segmentSampleCount = 0
        nextWindowEnd = frameSize
    }

    // MARK: - Ring buffer

    private func beginSegment(sampleRate: Double) {
        if let previous = currentSampleRate {
            timeOffset += Double(segmentSampleCount) / previous
        }
        currentSampleRate = sampleRate
        // Math.round in the web code; rates and hops are positive, so
        // rounding half away from zero is equivalent.
        hopSamples = Swift.max(1, Int((hopSeconds * sampleRate).rounded()))
        segmentSampleCount = 0
        nextWindowEnd = frameSize
        for i in ring.indices { ring[i] = 0 }
        ringWriteIndex = 0
    }

    private func appendToRing(_ samples: [Float], from start: Int, count: Int) {
        // Only the last frameSize samples of a long run can survive.
        let skip = Swift.max(0, count - frameSize)
        var i = start + skip
        let end = start + count
        while i < end {
            ring[ringWriteIndex] = samples[i]
            ringWriteIndex += 1
            if ringWriteIndex == frameSize { ringWriteIndex = 0 }
            i += 1
        }
    }

    /// The last frameSize samples in chronological order.
    private func currentWindow() -> [Float] {
        if ringWriteIndex == 0 { return ring }
        var window = [Float]()
        window.reserveCapacity(frameSize)
        window.append(contentsOf: ring[ringWriteIndex...])
        window.append(contentsOf: ring[..<ringWriteIndex])
        return window
    }
}

// MARK: - Frame analysis and tracking

/// Pitch and loudness of one analysis window.
struct ProsodyFrameAnalysis: Equatable, Sendable {
    var f0: Double
    var clarity: Double
    var rms: Double
}

/// Accumulates analyzed frames for one recording. Port of ProsodyTracker in
/// lib/prosody/analysis.ts.
struct ProsodyTracker: Sendable {
    private struct StoredFrame: Sendable {
        var t: Double
        var analysis: ProsodyFrameAnalysis
    }

    private var frames: [StoredFrame] = []
    private var startT: Double?
    private var calibrationRms: [Double] = []
    private var floor: Double?
    private var liveSortedF0: [Double] = []
    private var liveRecentF0: [Double] = []

    /// Noise floor, or nil while still calibrating.
    var noiseFloor: Double? { floor }

    var frameCount: Int { frames.count }

    /// Adds one analyzed frame. `t` is in seconds and must be non-decreasing.
    /// Returns the frame to show on a live display.
    mutating func push(t: Double, _ a: ProsodyFrameAnalysis) -> ProsodyFrame {
        let rms = ProsodyMath.finiteOrZero(a.rms)
        let frame = StoredFrame(
            t: ProsodyMath.finiteOrZero(t),
            analysis: ProsodyFrameAnalysis(
                f0: ProsodyMath.finiteOrZero(a.f0),
                clarity: ProsodyMath.finiteOrZero(a.clarity),
                rms: rms
            )
        )
        frames.append(frame)
        let start = startT ?? frame.t
        startT = start

        let floor: Double
        if let existing = self.floor {
            floor = existing
        } else {
            if frame.t - start < ProsodyConstants.calibrationSeconds {
                calibrationRms.append(rms)
                return ProsodyFrame(t: frame.t, semitones: nil, rms: rms)
            }
            floor = ProsodyMath.computeNoiseFloor(calibrationRms)
            self.floor = floor
        }

        guard ProsodyMath.isVoiced(frame.analysis, noiseFloor: floor) else {
            liveRecentF0.removeAll()
            return ProsodyFrame(t: frame.t, semitones: nil, rms: rms)
        }

        ProsodyMath.insertSorted(&liveSortedF0, frame.analysis.f0)
        liveRecentF0.append(frame.analysis.f0)
        if liveRecentF0.count > ProsodyConstants.medianWindow { liveRecentF0.removeFirst() }
        // A short causal median keeps the live contour smooth without lag spikes.
        let smoothed = ProsodyMath.median(liveRecentF0)
        let semitones = ProsodyMath.semitones(from: smoothed, reference: ProsodyMath.sortedMedian(liveSortedF0))
        return ProsodyFrame(t: frame.t, semitones: semitones, rms: rms)
    }

    /// Computes summary statistics over everything pushed so far.
    func finish() -> ProsodyStats {
        guard !frames.isEmpty else { return ProsodyMath.emptyStats() }

        // If the recording ended inside the calibration period, calibrate on what we have.
        let floor = self.floor ?? ProsodyMath.computeNoiseFloor(calibrationRms)
        let voiced = frames.filter { ProsodyMath.isVoiced($0.analysis, noiseFloor: floor) }
        guard !voiced.isEmpty else { return ProsodyMath.emptyStats() }

        let reference = ProsodyMath.median(voiced.map { $0.analysis.f0 })
        let rawSemitones = voiced.map { ProsodyMath.semitones(from: $0.analysis.f0, reference: reference) }
        let track = ProsodyMath.dropOctaveJumps(
            ProsodyMath.medianFilter(rawSemitones, window: ProsodyConstants.medianWindow),
            maxJump: ProsodyConstants.maxJumpSemitones
        )
        let loudnessDb = voiced.map { 20 * log10(Swift.max($0.analysis.rms, 1e-9)) }

        let range = Swift.max(0, ProsodyMath.percentile(track, 95) - ProsodyMath.percentile(track, 5))
        let syllableRate = ProsodyMath.estimateSyllableRate(
            frames.map { (t: $0.t, analysis: $0.analysis) },
            noiseFloor: floor
        )
        return ProsodyStats(
            pitchRangeSemitones: ProsodyMath.finiteOrZero(range),
            pitchSdSemitones: ProsodyMath.finiteOrZero(ProsodyMath.standardDeviation(track)),
            loudnessSdDb: ProsodyMath.finiteOrZero(ProsodyMath.standardDeviation(loudnessDb)),
            wordsPerSec: ProsodyMath.finiteOrZero(syllableRate),
            voicedFrames: .init(voiced.count)
        )
    }
}

// MARK: - Numeric helpers

/// Numeric helpers ported from lib/prosody/analysis.ts. All return 0 for
/// empty input so statistics never become NaN.
enum ProsodyMath {
    static func finiteOrZero(_ x: Double) -> Double {
        x.isFinite ? x : 0
    }

    /// Root mean square amplitude of a sample window.
    static func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum = 0.0
        for s in samples {
            let d = Double(s)
            sum += d * d
        }
        return finiteOrZero((sum / Double(samples.count)).squareRoot())
    }

    /// Analyzes one window. Returns f0 = 0 and clarity = 0 when no pitch can
    /// be found or the window length does not match the detector.
    static func analyzeFrame(_ samples: [Float], sampleRate: Double, detector: PitchDetector) -> ProsodyFrameAnalysis {
        let rms = rms(samples)
        guard samples.count == detector.frameSize, sampleRate > 0 else {
            return ProsodyFrameAnalysis(f0: 0, clarity: 0, rms: rms)
        }
        let (f0, clarity) = detector.detect(samples, sampleRate: sampleRate)
        guard f0.isFinite, clarity.isFinite else {
            return ProsodyFrameAnalysis(f0: 0, clarity: 0, rms: rms)
        }
        return ProsodyFrameAnalysis(f0: f0, clarity: clarity, rms: rms)
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return sortedMedian(values.sorted())
    }

    static func sortedMedian(_ sorted: [Double]) -> Double {
        let n = sorted.count
        guard n > 0 else { return 0 }
        let mid = n >> 1
        return n % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// Percentile with linear interpolation, p in [0, 100].
    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = (Swift.min(Swift.max(p, 0), 100) / 100) * Double(sorted.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = Int(rank.rounded(.up))
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (rank - Double(lo))
    }

    /// Population standard deviation.
    static func standardDeviation(_ values: [Double]) -> Double {
        let n = values.count
        guard n >= 2 else { return 0 }
        var mean = 0.0
        for v in values { mean += v }
        mean /= Double(n)
        var sq = 0.0
        for v in values { sq += (v - mean) * (v - mean) }
        return finiteOrZero((sq / Double(n)).squareRoot())
    }

    /// Centered median filter; the window shrinks symmetrically at the edges.
    static func medianFilter(_ values: [Double], window: Int = ProsodyConstants.medianWindow) -> [Double] {
        let half = Swift.max(0, window / 2)
        var out = [Double](repeating: 0, count: values.count)
        for i in values.indices {
            let reach = Swift.min(half, i, values.count - 1 - i)
            out[i] = median(Array(values[(i - reach)...(i + reach)]))
        }
        return out
    }

    /// Removes isolated octave errors: a value is dropped when it differs by
    /// more than maxJump from every neighbor it has. Runs of one or two bad
    /// frames are already removed by the median filter, so this catches what
    /// survives it.
    static func dropOctaveJumps(_ values: [Double], maxJump: Double = ProsodyConstants.maxJumpSemitones) -> [Double] {
        guard values.count >= 2 else { return values }
        var out: [Double] = []
        for i in values.indices {
            let v = values[i]
            let prevJump = i > 0 ? abs(v - values[i - 1]) > maxJump : true
            let nextJump = i < values.count - 1 ? abs(v - values[i + 1]) > maxJump : true
            if !(prevJump && nextJump) { out.append(v) }
        }
        return out
    }

    static func semitones(from f0: Double, reference: Double) -> Double {
        guard f0 > 0, reference > 0 else { return 0 }
        return finiteOrZero(12 * log2(f0 / reference))
    }

    static func emptyStats() -> ProsodyStats {
        ProsodyStats(pitchRangeSemitones: 0, pitchSdSemitones: 0, loudnessSdDb: 0, wordsPerSec: 0, voicedFrames: 0)
    }

    /// Inserts into an ascending array, keeping it sorted.
    static func insertSorted(_ array: inout [Double], _ value: Double) {
        var lo = 0
        var hi = array.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            if array[mid] < value { lo = mid + 1 } else { hi = mid }
        }
        array.insert(value, at: lo)
    }

    static func computeNoiseFloor(_ calibrationRms: [Double]) -> Double {
        let raw = ProsodyConstants.noiseFloorFactor * median(calibrationRms)
        return Swift.min(ProsodyConstants.noiseFloorMax, Swift.max(ProsodyConstants.noiseFloorMin, finiteOrZero(raw)))
    }

    static func isVoiced(_ a: ProsodyFrameAnalysis, noiseFloor: Double) -> Bool {
        a.clarity >= ProsodyConstants.minClarity
            && a.f0 >= ProsodyConstants.minF0Hz
            && a.f0 <= ProsodyConstants.maxF0Hz
            && a.rms > noiseFloor
    }

    /// Approximate speaking rate. This is not a word count: it counts onsets
    /// of voiced segments, where segments are split by unvoiced gaps of at
    /// least segmentGapSeconds, and divides by the span from the first to the
    /// last voiced frame. Voiced segments roughly track syllable nuclei, so
    /// the result is a syllable-like rate useful for relative comparison only.
    static func estimateSyllableRate(_ frames: [(t: Double, analysis: ProsodyFrameAnalysis)], noiseFloor: Double) -> Double {
        var onsets = 0
        var firstVoicedT: Double?
        var lastVoicedT: Double?
        var gapStartT: Double?

        for f in frames {
            if isVoiced(f.analysis, noiseFloor: noiseFloor) {
                if lastVoicedT == nil {
                    onsets = 1
                    firstVoicedT = f.t
                } else if let gapStart = gapStartT, f.t - gapStart >= ProsodyConstants.segmentGapSeconds {
                    onsets += 1
                }
                lastVoicedT = f.t
                gapStartT = nil
            } else if lastVoicedT != nil && gapStartT == nil {
                gapStartT = f.t
            }
        }

        guard let first = firstVoicedT, let last = lastVoicedT else { return 0 }
        let span = last - first
        return span > 0 ? Double(onsets) / span : 0
    }
}
