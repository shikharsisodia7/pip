import { alignWords } from '@/lib/reading/align';
import type { ProbeItem, ProbeResult, Transcript } from '@/lib/types';

/** The five cards are one page, scored by the same alignment as story reading. */
export function scoreProbe(items: ProbeItem[], transcript: Transcript): ProbeResult {
  const alignment = alignWords(items.map((item) => item.word).join(' '), transcript);
  const results = items.map((item, index) => {
    const aligned = alignment.words.find((word) => word.index === index);
    return {
      ...item,
      correct: aligned?.status === 'correct' || aligned?.status === 'selfCorrected',
      ...(aligned?.said ? { said: aligned.said } : {}),
    };
  });
  return { items: results, correctCount: results.filter((item) => item.correct).length };
}
