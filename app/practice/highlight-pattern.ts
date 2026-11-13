import { getPattern } from '@/lib/patterns';

export interface PatternSegment { text: string; bold: boolean }

/** Preserve the printed word, including case and punctuation. */
export function highlightPattern(word: string, patternId: string): PatternSegment[] {
  if (!getPattern(patternId)?.test(word)) return [{ text: word, bold: false }];

  const expressions: Record<string, RegExp> = {
    ed: /ed(?=[^a-z]*$)/gi,
    'silent-e': /[aeiou][bcdfgklmnprstvz]e(?=[^a-z]*$)/gi,
    er: /er|ir|ur/gi,
    ai: /ai|ay/gi,
    oi: /oi|oy/gi,
  };
  const expression = expressions[patternId] ?? new RegExp(patternId, 'gi');
  const ranges: { start: number; end: number }[] = [];
  for (const match of word.matchAll(expression)) {
    if (patternId === 'silent-e') {
      // Show the vowel and the final e, with the consonant left unbolded.
      ranges.push({ start: match.index, end: match.index + 1 });
      ranges.push({ start: match.index + 2, end: match.index + 3 });
    } else {
      ranges.push({ start: match.index, end: match.index + match[0].length });
    }
  }

  const segments: PatternSegment[] = [];
  let cursor = 0;
  for (const { start, end } of ranges) {
    if (start > cursor) segments.push({ text: word.slice(cursor, start), bold: false });
    segments.push({ text: word.slice(start, end), bold: true });
    cursor = end;
  }
  if (cursor < word.length) segments.push({ text: word.slice(cursor), bold: false });
  return segments;
}
