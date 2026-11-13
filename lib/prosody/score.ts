/**
 * Expression scoring: compares an expressive attempt against the speaker's
 * own reading baseline.
 */
import type { ProsodyStats } from '@/lib/types';

export const DEFAULT_THRESHOLD = 1.25;

/** Denominator floors so a very flat baseline cannot inflate the ratio. */
export const BASELINE_PITCH_SD_FLOOR = 1.0;
export const BASELINE_LOUDNESS_SD_FLOOR = 1.5;

export const PITCH_WEIGHT = 0.6;
export const LOUDNESS_WEIGHT = 0.4;

/** Below this many voiced frames the baseline is not trusted. */
export const MIN_BASELINE_VOICED_FRAMES = 40;
/** Below this many voiced frames the attempt is treated as no attempt. */
export const MIN_ATTEMPT_VOICED_FRAMES = 10;

/** Absolute fallback: pitch SD (semitones) that counts as expressive. */
export const FALLBACK_PITCH_SD = 2.5;

// Kept in module state behind accessors, because a reassigned `export let`
// is awkward to consume through ESM live bindings and bundlers.
let threshold = DEFAULT_THRESHOLD;

export function getThreshold(): number {
  return threshold;
}

export function setThreshold(n: number): number {
  if (Number.isFinite(n)) threshold = Math.max(0, Math.round(n * 1000) / 1000);
  return threshold;
}

export function nudgeThreshold(delta: number): number {
  return setThreshold(threshold + (Number.isFinite(delta) ? delta : 0));
}

function finite(n: number): number {
  return Number.isFinite(n) ? n : 0;
}

/**
 * Scores an attempt relative to a baseline.
 *
 * With a usable baseline:
 *   score = 0.6 * attemptPitchSd / max(baselinePitchSd, 1.0)
 *         + 0.4 * attemptLoudnessSd / max(baselineLoudnessSd, 1.5)
 *   passed = score >= getThreshold()
 *
 * Without one (null, or fewer than 40 voiced frames), an absolute fallback:
 *   score = (attemptPitchSd / 2.5) * DEFAULT_THRESHOLD
 *   passed = attemptPitchSd >= 2.5
 * The mapping puts a pitch SD of 2.5 semitones exactly at the default
 * threshold, so the score stays on the same scale for the meter UI. The
 * fallback pass rule is absolute and does not move with the threshold.
 *
 * An attempt with fewer than 10 voiced frames scores 0 and does not pass.
 */
export function expressionScore(
  attempt: ProsodyStats,
  baseline: ProsodyStats | null,
): { score: number; passed: boolean } {
  if (!attempt || !(attempt.voicedFrames >= MIN_ATTEMPT_VOICED_FRAMES)) {
    return { score: 0, passed: false };
  }
  const pitchSd = Math.max(0, finite(attempt.pitchSdSemitones));
  const loudnessSd = Math.max(0, finite(attempt.loudnessSdDb));

  if (!baseline || !(baseline.voicedFrames >= MIN_BASELINE_VOICED_FRAMES)) {
    const score = finite((pitchSd / FALLBACK_PITCH_SD) * DEFAULT_THRESHOLD);
    return { score, passed: pitchSd >= FALLBACK_PITCH_SD };
  }

  const pitchDen = Math.max(finite(baseline.pitchSdSemitones), BASELINE_PITCH_SD_FLOOR);
  const loudDen = Math.max(finite(baseline.loudnessSdDb), BASELINE_LOUDNESS_SD_FLOOR);
  const score = finite(PITCH_WEIGHT * (pitchSd / pitchDen) + LOUDNESS_WEIGHT * (loudnessSd / loudDen));
  return { score, passed: score >= threshold };
}
