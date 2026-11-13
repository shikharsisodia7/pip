import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ProsodyFrame, ProsodyStats } from '@/lib/types';
import {
  DEFAULT_THRESHOLD,
  FRAME_SIZE,
  MIN_CLARITY,
  MIN_F0_HZ,
  ProsodyTracker,
  analyzeFrame,
  createDetector,
  createProsodyRecorder,
  dropOctaveJumps,
  expressionScore,
  getThreshold,
  medianFilter,
  nudgeThreshold,
  percentile,
  setThreshold,
} from '@/lib/prosody';

const SR = 44_100;
const HOP = Math.round(0.025 * SR); // about 25 ms, matching the browser poll interval
const LEAD_IN_SEC = 0.3;
const LEAD_IN_AMPLITUDE = 0.002; // low-level room noise ahead of the signal

/** Deterministic PRNG (mulberry32) so noise-based tests are reproducible. */
function rng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function noise(seconds: number, amplitude: number, seed: number): Float32Array {
  const rand = rng(seed);
  const out = new Float32Array(Math.round(seconds * SR));
  for (let i = 0; i < out.length; i++) out[i] = (rand() * 2 - 1) * amplitude;
  return out;
}

/**
 * Phase-continuous tone. freq(t) and amp(t) take seconds. A little background
 * noise is mixed in so the signal is not unrealistically clean.
 */
function tone(
  seconds: number,
  freq: (t: number) => number,
  amp: (t: number) => number,
  seed = 7,
): Float32Array {
  const bg = noise(seconds, LEAD_IN_AMPLITUDE, seed);
  const out = new Float32Array(bg.length);
  let phase = 0;
  for (let i = 0; i < out.length; i++) {
    const t = i / SR;
    phase += (2 * Math.PI * freq(t)) / SR;
    out[i] = amp(t) * Math.sin(phase) + bg[i];
  }
  return out;
}

function concat(...parts: Float32Array[]): Float32Array {
  const out = new Float32Array(parts.reduce((n, p) => n + p.length, 0));
  let offset = 0;
  for (const p of parts) {
    out.set(p, offset);
    offset += p.length;
  }
  return out;
}

/** Prepends the calibration lead-in so the adaptive noise floor is exercised. */
function withLeadIn(signal: Float32Array, seed = 1): Float32Array {
  return concat(noise(LEAD_IN_SEC, LEAD_IN_AMPLITUDE, seed), signal);
}

/** Feeds a signal through analyzeFrame and the tracker, window by window. */
function run(signal: Float32Array): { stats: ProsodyStats; frames: ProsodyFrame[] } {
  const detector = createDetector(FRAME_SIZE);
  const tracker = new ProsodyTracker();
  const frames: ProsodyFrame[] = [];
  for (let end = FRAME_SIZE; end <= signal.length; end += HOP) {
    const window = signal.subarray(end - FRAME_SIZE, end);
    frames.push(tracker.push(end / SR, analyzeFrame(window, SR, detector)));
  }
  return { stats: tracker.finish(), frames };
}

function expectNoNaN(stats: ProsodyStats): void {
  for (const [key, value] of Object.entries(stats)) {
    expect(Number.isFinite(value), `${key} should be finite`).toBe(true);
  }
}

/** Triangle wave 0 -> 1 -> 0 over `period` seconds. */
function triangle(t: number, period: number): number {
  const x = (t % period) / period;
  return x < 0.5 ? x * 2 : 2 - x * 2;
}

// A plausible reading-aloud baseline: moderate intonation, plenty of frames.
const REALISTIC_BASELINE: ProsodyStats = {
  pitchRangeSemitones: 7,
  pitchSdSemitones: 2.2,
  loudnessSdDb: 4,
  wordsPerSec: 3,
  voicedFrames: 400,
};

// A monotone reading baseline: little pitch or loudness movement.
const FLAT_BASELINE: ProsodyStats = {
  pitchRangeSemitones: 2.5,
  pitchSdSemitones: 0.8,
  loudnessSdDb: 1.8,
  wordsPerSec: 3,
  voicedFrames: 400,
};

const steady = withLeadIn(
  tone(
    3,
    () => 200,
    (t) => 0.1 * (1 + 0.1 * Math.sin(2 * Math.PI * 2 * t)),
  ),
);

// 150 Hz -> 350 Hz -> 150 Hz over 3 s, with slow amplitude modulation.
const sweep = withLeadIn(
  tone(
    3,
    (t) => 150 + 200 * triangle(t, 3),
    (t) => 0.15 * (1 + 0.6 * Math.sin(2 * Math.PI * 1.5 * t)),
  ),
);

beforeEach(() => {
  setThreshold(DEFAULT_THRESHOLD);
});

describe('analyzeFrame', () => {
  it('finds a 200 Hz tone with high clarity', () => {
    const detector = createDetector(FRAME_SIZE);
    const sig = tone(0.1, () => 200, () => 0.2);
    const a = analyzeFrame(sig.subarray(0, FRAME_SIZE), SR, detector);
    expect(a.f0).toBeGreaterThan(198);
    expect(a.f0).toBeLessThan(202);
    expect(a.clarity).toBeGreaterThan(0.95);
    expect(a.rms).toBeGreaterThan(0.13);
    expect(a.rms).toBeLessThan(0.15);
  });

  it('returns zeros for a window of the wrong length instead of throwing', () => {
    const detector = createDetector(FRAME_SIZE);
    const a = analyzeFrame(new Float32Array(100), SR, detector);
    expect(a).toEqual({ f0: 0, clarity: 0, rms: 0 });
  });
});

describe('ProsodyTracker with synthetic signals', () => {
  it('(1) steady 200 Hz tone has almost no pitch movement and fails against a realistic baseline', () => {
    const { stats } = run(steady);
    expectNoNaN(stats);
    expect(stats.voicedFrames).toBeGreaterThan(100);
    expect(stats.pitchSdSemitones).toBeLessThan(0.5);
    expect(stats.pitchRangeSemitones).toBeLessThan(0.5);
    expect(stats.loudnessSdDb).toBeLessThan(1);

    const result = expressionScore(stats, REALISTIC_BASELINE);
    expect(result.passed).toBe(false);
    expect(result.score).toBeLessThan(0.3);
  });

  it('(2) wide slow pitch sweep with amplitude modulation passes against a flat baseline', () => {
    const { stats } = run(sweep);
    expectNoNaN(stats);
    expect(stats.voicedFrames).toBeGreaterThan(100);
    // The sweep spans 12 * log2(350 / 150), about 14.7 semitones.
    expect(stats.pitchRangeSemitones).toBeGreaterThan(10);
    expect(stats.pitchSdSemitones).toBeGreaterThan(3);
    expect(stats.loudnessSdDb).toBeGreaterThan(3);

    const result = expressionScore(stats, FLAT_BASELINE);
    expect(result.passed).toBe(true);
    expect(result.score).toBeGreaterThan(2 * DEFAULT_THRESHOLD);

    // It also clears a realistic baseline, while the steady tone does not.
    expect(expressionScore(stats, REALISTIC_BASELINE).passed).toBe(true);
  });

  it('(2b) a baseline measured from a mildly intoned signal separates the two attempts', () => {
    const mild = withLeadIn(
      tone(
        3,
        (t) => 200 * Math.pow(2, (2 * Math.sin(2 * Math.PI * 0.7 * t)) / 12),
        (t) => 0.12 * (1 + 0.25 * Math.sin(2 * Math.PI * 2.5 * t)),
        11,
      ),
    );
    const baseline = run(mild).stats;
    expect(baseline.voicedFrames).toBeGreaterThanOrEqual(40);
    expect(expressionScore(run(steady).stats, baseline).passed).toBe(false);
    expect(expressionScore(run(sweep).stats, baseline).passed).toBe(true);
  });

  it('(3) silence gives zero voiced frames and all-zero stats', () => {
    const { stats, frames } = run(new Float32Array(SR * 2));
    expectNoNaN(stats);
    expect(stats).toEqual({
      pitchRangeSemitones: 0,
      pitchSdSemitones: 0,
      loudnessSdDb: 0,
      wordsPerSec: 0,
      voicedFrames: 0,
    });
    expect(frames.every((f) => f.semitones === null)).toBe(true);
    expect(expressionScore(stats, REALISTIC_BASELINE)).toEqual({ score: 0, passed: false });
  });

  it('(4) loud white noise is rejected by the clarity gate', () => {
    const loudNoise = noise(3, 0.2, 99);

    // The clarity gate alone rejects the vast majority of noise frames. The
    // few that slip past report an f0 near sampleRate / FRAME_SIZE (about
    // 22 Hz, an edge-of-window artifact), which the f0 range gate removes.
    const detector = createDetector(FRAME_SIZE);
    let total = 0;
    let clear = 0;
    for (let end = FRAME_SIZE; end <= loudNoise.length; end += HOP) {
      const a = analyzeFrame(loudNoise.subarray(end - FRAME_SIZE, end), SR, detector);
      total++;
      if (a.clarity >= MIN_CLARITY) {
        clear++;
        expect(a.f0).toBeLessThan(MIN_F0_HZ);
      }
    }
    expect(clear / total).toBeLessThan(0.08);

    const { stats } = run(withLeadIn(loudNoise));
    expectNoNaN(stats);
    expect(stats.voicedFrames).toBe(0);
    expect(expressionScore(stats, null).passed).toBe(false);
  });

  it('caps the noise floor when speech starts during calibration', () => {
    // No lead-in: the calibration period measures the tone itself. Without
    // the cap the floor would sit above the tone and nothing would be voiced.
    const { stats } = run(tone(2, () => 200, () => 0.15));
    expect(stats.voicedFrames).toBeGreaterThan(60);
  });

  it('a tone quieter than the calibrated noise floor is not voiced', () => {
    // Loud lead-in raises the floor; the following clean tone sits below it.
    const sig = concat(noise(LEAD_IN_SEC, 0.006, 5), tone(1, () => 200, () => 0.003));
    expect(run(sig).stats.voicedFrames).toBe(0);
  });

  it('emits live frames with null semitones during calibration and numbers once voiced', () => {
    const { frames } = run(sweep);
    const calibrating = frames.filter((f) => f.t < LEAD_IN_SEC);
    expect(calibrating.length).toBeGreaterThan(0);
    expect(calibrating.every((f) => f.semitones === null)).toBe(true);
    const live = frames.filter((f) => f.semitones !== null);
    expect(live.length).toBeGreaterThan(80);
    expect(live.every((f) => Number.isFinite(f.semitones) && Number.isFinite(f.rms))).toBe(true);
    const values = live.map((f) => f.semitones as number);
    expect(Math.max(...values) - Math.min(...values)).toBeGreaterThan(8);
  });

  it('estimates an approximate syllable-like rate from voiced bursts', () => {
    // 4 bursts per second: 150 ms tone, 100 ms gap, for 2 s.
    const bursts = tone(
      2,
      () => 220,
      (t) => ((t % 0.25) < 0.15 ? 0.15 : 0),
    );
    const { stats } = run(withLeadIn(bursts));
    expect(stats.wordsPerSec).toBeGreaterThan(3);
    expect(stats.wordsPerSec).toBeLessThan(5.5);

    // A continuous tone has a single onset over its whole span.
    expect(run(steady).stats.wordsPerSec).toBeLessThan(0.5);
  });

  it('finish() on an empty tracker returns zeros', () => {
    const stats = new ProsodyTracker().finish();
    expectNoNaN(stats);
    expect(stats.voicedFrames).toBe(0);
  });
});

describe('track cleanup helpers', () => {
  it('median filter removes a two-frame octave error', () => {
    const track = [0, 0.2, 0.1, 12, 12.1, 0.3, 0.2, 0.1];
    const filtered = medianFilter(track, 5);
    expect(Math.max(...filtered)).toBeLessThan(1);
  });

  it('drops an isolated jump larger than 10 semitones', () => {
    expect(dropOctaveJumps([0, 0.5, 12, 0.4, 0.2])).toEqual([0, 0.5, 0.4, 0.2]);
    expect(dropOctaveJumps([12, 0.5, 0.4])).toEqual([0.5, 0.4]);
  });

  it('percentile interpolates and handles empty input', () => {
    expect(percentile([], 50)).toBe(0);
    expect(percentile([0, 10], 50)).toBe(5);
  });
});

describe('expressionScore', () => {
  const expressive: ProsodyStats = {
    pitchRangeSemitones: 10,
    pitchSdSemitones: 3,
    loudnessSdDb: 5,
    wordsPerSec: 3,
    voicedFrames: 120,
  };
  const monotone: ProsodyStats = { ...expressive, pitchSdSemitones: 1.2, loudnessSdDb: 2 };

  it('(5) falls back to an absolute pitch SD rule when the baseline is null or too short', () => {
    const shortBaseline: ProsodyStats = { ...REALISTIC_BASELINE, voicedFrames: 39 };
    for (const baseline of [null, shortBaseline]) {
      const pass = expressionScore(expressive, baseline);
      expect(pass.passed).toBe(true);
      expect(pass.score).toBeCloseTo((3 / 2.5) * DEFAULT_THRESHOLD, 6);

      const fail = expressionScore(monotone, baseline);
      expect(fail.passed).toBe(false);
      expect(fail.score).toBeLessThan(DEFAULT_THRESHOLD);
    }
    // Exactly 2.5 semitones lands on the default threshold and passes.
    const edge = expressionScore({ ...expressive, pitchSdSemitones: 2.5 }, null);
    expect(edge.passed).toBe(true);
    expect(edge.score).toBeCloseTo(DEFAULT_THRESHOLD, 6);
  });

  it('returns 0 and false when the attempt has fewer than 10 voiced frames', () => {
    expect(expressionScore({ ...expressive, voicedFrames: 9 }, REALISTIC_BASELINE)).toEqual({
      score: 0,
      passed: false,
    });
    expect(expressionScore({ ...expressive, voicedFrames: 9 }, null)).toEqual({
      score: 0,
      passed: false,
    });
  });

  it('applies the weighted ratio with denominator floors', () => {
    const tinyBaseline: ProsodyStats = {
      ...REALISTIC_BASELINE,
      pitchSdSemitones: 0.1,
      loudnessSdDb: 0.2,
    };
    // Floors: 1.0 for pitch, 1.5 for loudness.
    const { score } = expressionScore(expressive, tinyBaseline);
    expect(score).toBeCloseTo(0.6 * (3 / 1.0) + 0.4 * (5 / 1.5), 6);
  });

  it('never returns NaN for degenerate input', () => {
    const bad = { ...expressive, pitchSdSemitones: NaN, loudnessSdDb: Infinity };
    const r = expressionScore(bad, { ...REALISTIC_BASELINE, pitchSdSemitones: NaN });
    expect(Number.isFinite(r.score)).toBe(true);
  });

  it('(6) threshold can be read, set and nudged', () => {
    expect(getThreshold()).toBe(1.25);
    // Score here is 0.6 * 2.2 / 2.2 + 0.4 * 4 / 4 = 1.0 against itself.
    const same = { ...REALISTIC_BASELINE };
    expect(expressionScore(same, REALISTIC_BASELINE).passed).toBe(false);

    for (let i = 0; i < 5; i++) nudgeThreshold(-0.05);
    expect(getThreshold()).toBe(1);
    expect(expressionScore(same, REALISTIC_BASELINE).passed).toBe(true);

    expect(nudgeThreshold(0.05)).toBe(1.05);
    expect(expressionScore(same, REALISTIC_BASELINE).passed).toBe(false);

    expect(setThreshold(2)).toBe(2);
    expect(setThreshold(NaN)).toBe(2);
    expect(setThreshold(-1)).toBe(0);
  });
});

describe('createProsodyRecorder outside the browser', () => {
  it('can be created without window and stop() without start() returns zero stats', async () => {
    const recorder = createProsodyRecorder();
    const unsubscribe = recorder.onFrame(() => {});
    expect(typeof unsubscribe).toBe('function');
    unsubscribe();
    const stats = await recorder.stop();
    expect(stats.voicedFrames).toBe(0);
    expectNoNaN(stats);
  });

  it('start() rejects cleanly when no microphone API exists, and stop() still works', async () => {
    const recorder = createProsodyRecorder();
    await expect(recorder.start()).rejects.toThrow(/not available/);
    expect((await recorder.stop()).voicedFrames).toBe(0);
  });
});

describe('createProsodyRecorder with a stubbed browser', () => {
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  function stubBrowser() {
    const calls = { getUserMedia: 0, trackStops: 0, closes: 0 };
    let phase = 0;
    class FakeAnalyser {
      fftSize = 2048;
      smoothingTimeConstant = 0.8;
      getFloatTimeDomainData(buf: Float32Array) {
        for (let i = 0; i < buf.length; i++) {
          buf[i] = 0.2 * Math.sin(phase);
          phase += (2 * Math.PI * 200) / 48_000;
        }
      }
    }
    class FakeAudioContext {
      sampleRate = 48_000;
      state: 'running' | 'closed' = 'running';
      createMediaStreamSource() {
        return { connect() {}, disconnect() {} };
      }
      createAnalyser() {
        return new FakeAnalyser();
      }
      async resume() {}
      async close() {
        calls.closes++;
        this.state = 'closed';
      }
    }
    const stream = { getTracks: () => [{ stop: () => calls.trackStops++ }] };
    vi.stubGlobal('window', { AudioContext: FakeAudioContext });
    vi.stubGlobal('navigator', {
      mediaDevices: {
        getUserMedia: async () => {
          calls.getUserMedia++;
          return stream;
        },
      },
    });
    return calls;
  }

  it('start() twice opens one stream, frames flow, and stop() releases everything', async () => {
    vi.useFakeTimers();
    const calls = stubBrowser();
    const recorder = createProsodyRecorder();
    const received: ProsodyFrame[] = [];
    recorder.onFrame((f) => received.push(f));

    await Promise.all([recorder.start(), recorder.start()]);
    await recorder.start();
    expect(calls.getUserMedia).toBe(1);

    vi.advanceTimersByTime(1500);
    expect(received.length).toBeGreaterThan(40);

    const stats = await recorder.stop();
    expect(stats.voicedFrames).toBeGreaterThan(20);
    expect(stats.pitchSdSemitones).toBeLessThan(0.5);
    expect(calls.trackStops).toBe(1);
    expect(calls.closes).toBe(1);

    // No more frames after stop, and a second stop() is harmless.
    const count = received.length;
    vi.advanceTimersByTime(500);
    expect(received.length).toBe(count);
    expect((await recorder.stop()).voicedFrames).toBe(0);
  });
});
