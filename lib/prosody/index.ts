import type { ProsodyFrame, ProsodyStats } from '@/lib/types';

export interface ProsodyRecorder {
  start(): Promise<void>;
  stop(): Promise<ProsodyStats>;
  onFrame(cb: (f: ProsodyFrame) => void): () => void;   // returns unsubscribe
}

const ZERO: ProsodyStats = {
  pitchRangeSemitones: 0, pitchSdSemitones: 0, loudnessSdDb: 0, wordsPerSec: 0, voicedFrames: 0,
};

/** Placeholder recorder: records nothing and returns zeros. */
export function createProsodyRecorder(): ProsodyRecorder {
  return {
    async start() {},
    async stop() {
      return { ...ZERO };
    },
    onFrame() {
      return () => {};
    },
  };
}

/** Placeholder score. */
export function expressionScore(
  attempt: ProsodyStats, baseline: ProsodyStats | null,
): { score: number; passed: boolean } {
  void attempt;
  void baseline;
  return { score: 0, passed: false };
}
