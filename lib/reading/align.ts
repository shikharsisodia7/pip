import { fuzzyEqual, normalizeToken, tokenizeDisplay } from '@/lib/text';
import type { AlignmentResult, AlignedWord, Transcript } from '@/lib/types';

/**
 * Placeholder alignment: compares words position by position.
 * Replaced by a full sequence alignment (substitutions, omissions, insertions,
 * self-corrections, hesitations). AlignedWord.expected is the normalized page word.
 */
export function alignWords(expectedText: string, transcript: Transcript): AlignmentResult {
  const expected = tokenizeDisplay(expectedText);
  const said = transcript.words;
  const words: AlignedWord[] = expected.map((e, index) => {
    const w = said[index];
    if (!w) return { index, expected: e.norm, status: 'omission' };
    const ok = fuzzyEqual(w.text, e.norm);
    return {
      index,
      expected: e.norm,
      status: ok ? 'correct' : 'substitution',
      said: ok ? undefined : normalizeToken(w.text),
      start: w.start,
      end: w.end,
    };
  });
  return { words, insertions: [] };
}
