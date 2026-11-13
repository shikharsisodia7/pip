/**
 * Pure prosody analysis: per-frame pitch and loudness, plus a tracker that
 * turns a stream of frames into live display frames and summary statistics.
 *
 * Nothing in this file touches browser APIs, so it runs (and is unit tested)
 * in Node. The browser recorder in ./index.ts feeds it microphone frames.
 */
import { PitchDetector } from 'pitchy';
import type { ProsodyFrame, ProsodyStats } from '@/lib/types';

/** Analysis window length in samples. Matches AnalyserNode fftSize. */
export const FRAME_SIZE = 2048;

/** Voicing gate: minimum pitchy clarity for a frame to count as voiced. */
export const MIN_CLARITY = 0.9;
/** Voicing gate: plausible f0 range for a child or adult speaking voice, Hz. */
export const MIN_F0_HZ = 80;
export const MAX_F0_HZ = 600;

/** Length of the noise floor calibration period at the start of a recording. */
export const CALIBRATION_SEC = 0.3;
/** Noise floor = clamp(NOISE_FLOOR_FACTOR x median calibration RMS). */
export const NOISE_FLOOR_FACTOR = 2.5;
export const NOISE_FLOOR_MIN = 1e-4;
/**
 * Upper bound on the noise floor. If the speaker starts talking during the
 * calibration period, the measured "noise" is actually speech, and an
 * unbounded floor would reject the rest of the recording. Normal speech into
 * a laptop or tablet microphone sits well above this level.
 */
export const NOISE_FLOOR_MAX = 0.02;

/** Median filter window applied to the voiced semitone track. */
export const MEDIAN_WINDOW = 5;
/** A voiced frame further than this from its neighbors is treated as an octave error. */
export const MAX_JUMP_SEMITONES = 10;
/** Unvoiced gap that separates two voiced segments for the speaking rate estimate. */
export const SEGMENT_GAP_SEC = 0.08;

export type FrameAnalysis = { f0: number; clarity: number; rms: number };

export type FramePitchDetector = PitchDetector<Float32Array>;

/** Creates a pitch detector sized for FRAME_SIZE windows. */
export function createDetector(size: number = FRAME_SIZE): FramePitchDetector {
  return PitchDetector.forFloat32Array(size);
}

/** Root mean square amplitude of a sample window. */
export function computeRms(samples: Float32Array): number {
  const n = samples.length;
  if (n === 0) return 0;
  let sum = 0;
  for (let i = 0; i < n; i++) {
    const s = samples[i];
    sum += s * s;
  }
  const rms = Math.sqrt(sum / n);
  return Number.isFinite(rms) ? rms : 0;
}

/**
 * Analyzes one window of audio. Returns f0 = 0 and clarity = 0 when no pitch
 * can be found or the window length does not match the detector.
 */
export function analyzeFrame(
  samples: Float32Array,
  sampleRate: number,
  detector: FramePitchDetector,
): FrameAnalysis {
  const rms = computeRms(samples);
  if (samples.length !== detector.inputLength || !(sampleRate > 0)) {
    return { f0: 0, clarity: 0, rms };
  }
  let f0 = 0;
  let clarity = 0;
  try {
    [f0, clarity] = detector.findPitch(samples, sampleRate);
  } catch {
    return { f0: 0, clarity: 0, rms };
  }
  if (!Number.isFinite(f0) || !Number.isFinite(clarity)) return { f0: 0, clarity: 0, rms };
  return { f0, clarity, rms };
}

// ---------------------------------------------------------------------------
// Small numeric helpers. All return 0 for empty input so stats never go NaN.
// ---------------------------------------------------------------------------

export function median(values: readonly number[]): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 === 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/** Percentile with linear interpolation, p in [0, 100]. */
export function percentile(values: readonly number[], p: number): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const rank = (Math.min(Math.max(p, 0), 100) / 100) * (sorted.length - 1);
  const lo = Math.floor(rank);
  const hi = Math.ceil(rank);
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (rank - lo);
}

/** Population standard deviation. */
export function standardDeviation(values: readonly number[]): number {
  const n = values.length;
  if (n < 2) return 0;
  let mean = 0;
  for (const v of values) mean += v;
  mean /= n;
  let sq = 0;
  for (const v of values) sq += (v - mean) * (v - mean);
  const sd = Math.sqrt(sq / n);
  return Number.isFinite(sd) ? sd : 0;
}

/** Centered median filter; the window shrinks symmetrically at the edges. */
export function medianFilter(values: readonly number[], window: number = MEDIAN_WINDOW): number[] {
  const half = Math.max(0, Math.floor(window / 2));
  const out: number[] = new Array(values.length);
  for (let i = 0; i < values.length; i++) {
    const reach = Math.min(half, i, values.length - 1 - i);
    out[i] = median(values.slice(i - reach, i + reach + 1));
  }
  return out;
}

/**
 * Removes isolated octave errors: a value is dropped when it differs by more
 * than maxJump from every neighbor it has. Runs of one or two bad frames are
 * already removed by the median filter, so this catches what survives it.
 */
export function dropOctaveJumps(
  values: readonly number[],
  maxJump: number = MAX_JUMP_SEMITONES,
): number[] {
  if (values.length < 2) return [...values];
  const out: number[] = [];
  for (let i = 0; i < values.length; i++) {
    const v = values[i];
    const prevJump = i > 0 ? Math.abs(v - values[i - 1]) > maxJump : true;
    const nextJump = i < values.length - 1 ? Math.abs(v - values[i + 1]) > maxJump : true;
    if (!(prevJump && nextJump)) out.push(v);
  }
  return out;
}

export function semitonesFrom(f0: number, reference: number): number {
  if (!(f0 > 0) || !(reference > 0)) return 0;
  const st = 12 * Math.log2(f0 / reference);
  return Number.isFinite(st) ? st : 0;
}

export function emptyStats(): ProsodyStats {
  return {
    pitchRangeSemitones: 0,
    pitchSdSemitones: 0,
    loudnessSdDb: 0,
    wordsPerSec: 0,
    voicedFrames: 0,
  };
}

function finiteOrZero(n: number): number {
  return Number.isFinite(n) ? n : 0;
}

/** Inserts into an ascending array, keeping it sorted. */
function insertSorted(arr: number[], v: number): void {
  let lo = 0;
  let hi = arr.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (arr[mid] < v) lo = mid + 1;
    else hi = mid;
  }
  arr.splice(lo, 0, v);
}

function sortedMedian(sorted: readonly number[]): number {
  const n = sorted.length;
  if (n === 0) return 0;
  const mid = n >> 1;
  return n % 2 === 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

type StoredFrame = FrameAnalysis & { t: number };

/**
 * Accumulates analyzed frames for one recording.
 *
 * Live output (push) uses only information available so far: frames are
 * reported as unvoiced until the noise floor calibration completes, and
 * semitones are relative to a running median of voiced f0.
 *
 * Final output (finish) re-evaluates every stored frame with the calibrated
 * noise floor and the speaker's overall median f0.
 */
export class ProsodyTracker {
  private frames: StoredFrame[] = [];
  private startT: number | null = null;
  private calibrationRms: number[] = [];
  private floor: number | null = null;
  private liveSortedF0: number[] = [];
  private liveRecentF0: number[] = [];

  /** Noise floor, or null while still calibrating. */
  get noiseFloor(): number | null {
    return this.floor;
  }

  get frameCount(): number {
    return this.frames.length;
  }

  /**
   * Adds one analyzed frame. t is in seconds and must be non-decreasing.
   * Returns the frame to show on a live display.
   */
  push(t: number, a: FrameAnalysis): ProsodyFrame {
    const rms = finiteOrZero(a.rms);
    const frame: StoredFrame = {
      t: finiteOrZero(t),
      f0: finiteOrZero(a.f0),
      clarity: finiteOrZero(a.clarity),
      rms,
    };
    this.frames.push(frame);
    if (this.startT === null) this.startT = frame.t;

    if (this.floor === null) {
      if (frame.t - this.startT < CALIBRATION_SEC) {
        this.calibrationRms.push(rms);
        return { t: frame.t, semitones: null, rms };
      }
      this.floor = computeNoiseFloor(this.calibrationRms);
    }

    if (!isVoiced(frame, this.floor)) {
      this.liveRecentF0 = [];
      return { t: frame.t, semitones: null, rms };
    }

    insertSorted(this.liveSortedF0, frame.f0);
    this.liveRecentF0.push(frame.f0);
    if (this.liveRecentF0.length > MEDIAN_WINDOW) this.liveRecentF0.shift();
    // A short causal median keeps the live contour smooth without lag spikes.
    const smoothed = median(this.liveRecentF0);
    const semitones = semitonesFrom(smoothed, sortedMedian(this.liveSortedF0));
    return { t: frame.t, semitones, rms };
  }

  /** Convenience: analyze a raw window and push it. */
  pushSamples(
    t: number,
    samples: Float32Array,
    sampleRate: number,
    detector: FramePitchDetector,
  ): ProsodyFrame {
    return this.push(t, analyzeFrame(samples, sampleRate, detector));
  }

  /** Computes summary statistics over everything pushed so far. */
  finish(): ProsodyStats {
    if (this.frames.length === 0) return emptyStats();

    // If the recording ended inside the calibration period, calibrate on what we have.
    const floor = this.floor ?? computeNoiseFloor(this.calibrationRms);
    const voiced = this.frames.filter((f) => isVoiced(f, floor));
    if (voiced.length === 0) return emptyStats();

    const reference = median(voiced.map((f) => f.f0));
    const rawSemitones = voiced.map((f) => semitonesFrom(f.f0, reference));
    const track = dropOctaveJumps(medianFilter(rawSemitones, MEDIAN_WINDOW), MAX_JUMP_SEMITONES);

    const loudnessDb = voiced.map((f) => 20 * Math.log10(Math.max(f.rms, 1e-9)));

    return {
      pitchRangeSemitones: finiteOrZero(Math.max(0, percentile(track, 95) - percentile(track, 5))),
      pitchSdSemitones: finiteOrZero(standardDeviation(track)),
      loudnessSdDb: finiteOrZero(standardDeviation(loudnessDb)),
      wordsPerSec: finiteOrZero(estimateSyllableRate(this.frames, floor)),
      voicedFrames: voiced.length,
    };
  }

  /** Clears all state so the tracker can be reused for a new recording. */
  reset(): void {
    this.frames = [];
    this.startT = null;
    this.calibrationRms = [];
    this.floor = null;
    this.liveSortedF0 = [];
    this.liveRecentF0 = [];
  }
}

export function computeNoiseFloor(calibrationRms: readonly number[]): number {
  const raw = NOISE_FLOOR_FACTOR * median(calibrationRms);
  return Math.min(NOISE_FLOOR_MAX, Math.max(NOISE_FLOOR_MIN, finiteOrZero(raw)));
}

export function isVoiced(a: FrameAnalysis, noiseFloor: number): boolean {
  return (
    a.clarity >= MIN_CLARITY && a.f0 >= MIN_F0_HZ && a.f0 <= MAX_F0_HZ && a.rms > noiseFloor
  );
}

/**
 * Approximate speaking rate. This is not a word count: it counts onsets of
 * voiced segments, where segments are split by unvoiced gaps of at least
 * SEGMENT_GAP_SEC, and divides by the span from the first to the last voiced
 * frame. Voiced segments roughly track syllable nuclei, so the result is a
 * syllable-like rate that is useful for relative comparison only.
 */
function estimateSyllableRate(frames: readonly StoredFrame[], floor: number): number {
  let onsets = 0;
  let firstVoicedT: number | null = null;
  let lastVoicedT: number | null = null;
  let gapStartT: number | null = null;

  for (const f of frames) {
    if (isVoiced(f, floor)) {
      if (lastVoicedT === null) {
        onsets = 1;
        firstVoicedT = f.t;
      } else if (gapStartT !== null && f.t - gapStartT >= SEGMENT_GAP_SEC) {
        onsets++;
      }
      lastVoicedT = f.t;
      gapStartT = null;
    } else if (lastVoicedT !== null && gapStartT === null) {
      gapStartT = f.t;
    }
  }

  if (firstVoicedT === null || lastVoicedT === null) return 0;
  const span = lastVoicedT - firstVoicedT;
  return span > 0 ? onsets / span : 0;
}
