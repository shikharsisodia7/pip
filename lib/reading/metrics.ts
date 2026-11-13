import type { AlignmentResult, ReadingMetrics } from '@/lib/types';

/** Placeholder metrics; refined alongside the real alignment. */
export function computeMetrics(alignment: AlignmentResult): ReadingMetrics {
  const words = alignment.words;
  const wordsTotal = words.length;
  const wordsCorrect = words.filter((w) => w.status === 'correct' || w.status === 'selfCorrected').length;
  const timed = words.filter((w) => w.start !== undefined && w.end !== undefined);
  const first = timed.length ? Math.min(...timed.map((w) => w.start!)) : 0;
  const last = timed.length ? Math.max(...timed.map((w) => w.end!)) : 0;
  const durationSec = Math.max(0, last - first);
  return {
    wcpm: durationSec > 0 ? Math.round(wordsCorrect / (durationSec / 60)) : 0,
    accuracyPct: wordsTotal ? Math.round((100 * wordsCorrect) / wordsTotal) : 0,
    wordsCorrect,
    wordsTotal,
    durationSec: Math.round(durationSec * 100) / 100,
    hesitations: words.filter((w) => w.hesitationBeforeSec !== undefined).length,
    selfCorrections: words.filter((w) => w.status === 'selfCorrected').length,
  };
}
