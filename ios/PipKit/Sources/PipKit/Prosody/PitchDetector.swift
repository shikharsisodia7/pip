import Accelerate
import Foundation

/// Pitch detection with the McLeod pitch method (MPM).
///
/// This is a port of the `PitchDetector` class from the `pitchy` npm package
/// (version 4.1.0), which the web app uses through lib/prosody/analysis.ts.
/// The algorithm is described in "A Smarter Way to Find Pitch" by Philip
/// McLeod and Geoff Wyvill. The steps match pitchy one for one:
///
/// 1. Autocorrelation through an FFT of the zero padded window (length is the
///    next power of two at or above twice the window).
/// 2. Normalized square difference function (NSDF), equation (9) of the
///    paper, with the incremental m'(tau) update and the same early stop
///    once m'(tau) is no longer positive.
/// 3. Key maxima: the highest maximum between each positively sloped zero
///    crossing and the following negatively sloped one.
/// 4. The first key maximum at or above `cutoff * nMax` is chosen, where
///    `nMax` is the highest key maximum and `cutoff` is 0.9 (pitchy's
///    default clarity threshold, the constant k in the paper).
/// 5. Parabolic interpolation through the chosen index and its neighbors
///    refines the lag; the interpolated peak height is the clarity, clamped
///    to at most 1.
///
/// pitchy as used by the web app stores its intermediate buffers in
/// Float32Array. This port computes the transforms in double precision and
/// rounds to `Float` at the same buffer boundaries, so the clarity values
/// agree with pitchy to well within the tolerance the voicing gate needs.
///
/// The detector holds only immutable transform setups, so one instance can be
/// shared across threads. Scratch buffers are allocated per call.
public struct PitchDetector: Sendable {
    /// Key maximum cutoff (the constant k in the MPM paper). pitchy's default.
    public static let keyMaximumCutoff = 0.9

    /// Number of samples the detector expects per call.
    public let frameSize: Int

    private let transform: AutocorrelationTransform

    /// Creates a detector for windows of `frameSize` samples.
    public init(frameSize: Int = 2048) {
        precondition(frameSize >= 1, "frameSize must be at least one")
        self.frameSize = frameSize
        self.transform = AutocorrelationTransform(inputLength: frameSize)
    }

    /// Detects the pitch of one window.
    ///
    /// - Parameters:
    ///   - samples: Exactly `frameSize` mono samples.
    ///   - sampleRate: Sample rate of `samples`, in Hz.
    /// - Returns: The detected frequency in Hz and its clarity in [0, 1].
    ///   Returns (0, 0) when no key maximum exists (for example, an all-zero
    ///   window) or when the window length does not match `frameSize`. As in
    ///   pitchy, degenerate input can produce non-finite values; callers that
    ///   need finite output should check for that (ProsodyAnalyzer does).
    public func detect(_ samples: [Float], sampleRate: Double) -> (frequency: Double, clarity: Double) {
        guard samples.count == frameSize else { return (0, 0) }

        let nsdf = normalizedSquareDifference(samples)
        let keyIndices = Self.keyMaximumIndices(nsdf)
        guard !keyIndices.isEmpty else { return (0, 0) }

        var nMax = -Double.infinity
        for i in keyIndices {
            nMax = Swift.max(nMax, Double(nsdf[i]))
        }
        // Guaranteed to exist: the key maximum that produced nMax qualifies.
        let resultIndex = keyIndices.first { Double(nsdf[$0]) >= Self.keyMaximumCutoff * nMax } ?? keyIndices[0]

        let (refinedIndex, clarity) = Self.refineResultIndex(resultIndex, nsdf)
        return (sampleRate / refinedIndex, Swift.min(clarity, 1.0))
    }

    // MARK: - NSDF

    /// Computes the NSDF of `input` (equation (9) in the MPM paper).
    func normalizedSquareDifference(_ input: [Float]) -> [Float] {
        var nsdf = transform.autocorrelate(input)
        let n = input.count

        // m'(0) = 2 r'(0). Each later m'(tau) drops x[tau - 1]^2 and
        // x[n - tau]^2. The loop stops once m is no longer positive, which
        // also guards against division by zero; the remaining lags are 0.
        var m = 2 * Double(nsdf[0])
        var i = 0
        while i < n && m > 0 {
            nsdf[i] = Float(2 * Double(nsdf[i]) / m)
            let head = Double(input[i])
            let tail = Double(input[n - i - 1])
            m -= head * head + tail * tail
            i += 1
        }
        while i < n {
            nsdf[i] = 0
            i += 1
        }
        return nsdf
    }

    // MARK: - Peak picking

    /// Indices of the key maxima: the highest maximum between a positively
    /// sloped zero crossing and the next negatively sloped one. A maximum
    /// whose region never closes with a negative crossing is not reported.
    static func keyMaximumIndices(_ input: [Float]) -> [Int] {
        var keyIndices: [Int] = []
        var lookingForMaximum = false
        var max = -Float.infinity
        var maxIndex = -1

        var i = 1
        while i < input.count - 1 {
            if input[i - 1] <= 0 && input[i] > 0 {
                lookingForMaximum = true
                maxIndex = i
                max = input[i]
            } else if input[i - 1] > 0 && input[i] <= 0 {
                lookingForMaximum = false
                if maxIndex != -1 {
                    keyIndices.append(maxIndex)
                }
            } else if lookingForMaximum && input[i] > max {
                max = input[i]
                maxIndex = i
            }
            i += 1
        }
        return keyIndices
    }

    /// Fits a parabola through `index` and its two neighbors and returns the
    /// position and height of its vertex (section 5 of the MPM paper).
    /// `index` must be in 1...(data.count - 2), which key maxima always are.
    static func refineResultIndex(_ index: Int, _ data: [Float]) -> (index: Double, value: Double) {
        let x0 = Double(index - 1)
        let x1 = Double(index)
        let x2 = Double(index + 1)
        let y0 = Double(data[index - 1])
        let y1 = Double(data[index])
        let y2 = Double(data[index + 1])

        let a = y0 / 2 - y1 + y2 / 2
        let b = -(y0 / 2) * (x1 + x2) + y1 * (x0 + x2) - (y2 / 2) * (x0 + x1)
        let c = (y0 * x1 * x2) / 2 - y1 * x0 * x2 + (y2 * x0 * x1) / 2

        let xMax = -b / (2 * a)
        let yMax = a * xMax * xMax + b * xMax + c
        return (xMax, yMax)
    }
}

/// Computes the linear autocorrelation r'(tau), tau in 0..<inputLength, via a
/// zero padded FFT. Holds immutable vDSP setups only, so it is safe to share.
final class AutocorrelationTransform: @unchecked Sendable {
    let inputLength: Int
    let fftSize: Int
    private let forward: OpaquePointer?
    private let inverse: OpaquePointer?

    init(inputLength: Int) {
        self.inputLength = inputLength
        let size = Self.ceilPowerOfTwo(2 * inputLength)
        self.fftSize = size
        let forward = vDSP_DFT_zop_CreateSetupD(nil, vDSP_Length(size), .FORWARD)
        self.forward = forward
        self.inverse = forward.flatMap { vDSP_DFT_zop_CreateSetupD($0, vDSP_Length(size), .INVERSE) }
    }

    deinit {
        if let inverse { vDSP_DFT_DestroySetupD(inverse) }
        if let forward { vDSP_DFT_DestroySetupD(forward) }
    }

    /// Returns r'(tau) for tau in 0..<input.count, rounded to `Float` as
    /// pitchy's Float32Array output buffer would be.
    func autocorrelate(_ input: [Float]) -> [Float] {
        guard let forward, let inverse else { return directAutocorrelation(input) }

        let size = fftSize
        var re = [Double](repeating: 0, count: size)
        var im = [Double](repeating: 0, count: size)
        for i in 0..<input.count {
            re[i] = Double(input[i])
        }
        var specRe = [Double](repeating: 0, count: size)
        var specIm = [Double](repeating: 0, count: size)
        vDSP_DFT_ExecuteD(forward, re, im, &specRe, &specIm)

        // Power spectrum |X|^2. The spectrum and the power are rounded to
        // Float, matching pitchy's Float32Array transform buffer.
        for k in 0..<size {
            let xr = Double(Float(specRe[k]))
            let xi = Double(Float(specIm[k]))
            specRe[k] = Double(Float(xr * xr + xi * xi))
            specIm[k] = 0
        }

        vDSP_DFT_ExecuteD(inverse, specRe, specIm, &re, &im)

        // vDSP's inverse is unnormalized; divide by the transform length.
        let scale = 1 / Double(size)
        var out = [Float](repeating: 0, count: input.count)
        for i in 0..<input.count {
            out[i] = Float(re[i] * scale)
        }
        return out
    }

    /// Direct O(n^2) autocorrelation, used only if a DFT setup is unavailable.
    private func directAutocorrelation(_ input: [Float]) -> [Float] {
        let n = input.count
        let x = input.map(Double.init)
        var out = [Float](repeating: 0, count: n)
        for lag in 0..<n {
            var sum = 0.0
            for j in 0..<(n - lag) {
                sum += x[j] * x[j + lag]
            }
            out[lag] = Float(sum)
        }
        return out
    }

    static func ceilPowerOfTwo(_ value: Int) -> Int {
        var v = 1
        while v < value { v <<= 1 }
        return v
    }
}
