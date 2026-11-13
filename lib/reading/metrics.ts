import type { AlignmentResult, ReadingMetrics } from '@/lib/types';

/** Score page words over the time covered by their available timestamps. */
export function computeMetrics(alignment: AlignmentResult): ReadingMetrics {
  const words = alignment.words;
  const wordsTotal = words.length;
  const wordsCorrect = words.filter((w) => w.status === 'correct' || w.status === 'selfCorrected').length;
  let first = Infinity;
  let last = -Infinity;
  for (const word of words) {
    if (word.start !== undefined && word.end !== undefined
      && Number.isFinite(word.start) && Number.isFinite(word.end) && word.end >= word.start) {
      first = Math.min(first, word.start);
      last = Math.max(last, word.end);
    }
  }
  const durationSec = Math.max(0, last - first);
  return {
    wcpm: durationSec > 0 ? Math.round(wordsCorrect / (durationSec / 60)) : 0,
    accuracyPct: wordsTotal ? Math.round((100 * wordsCorrect) / wordsTotal) : 0,
    wordsCorrect,
    wordsTotal,
    durationSec: Math.round(durationSec * 100) / 100,
    hesitations: words.filter((w) => (w.hesitationBeforeSec ?? 0) > 0.8 + 1e-9).length,
    selfCorrections: words.filter((w) => w.status === 'selfCorrected').length,
  };
}
