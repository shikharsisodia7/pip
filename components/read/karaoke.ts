// Karaoke cursor for the Read screen: how far through the page the reader has got.
// Forgiving on purpose. It only ever moves forward, skips spoken words it cannot
// place, and lets the reader skip up to two page words, so a misread never
// freezes the highlight. Scoring happens separately in lib/reading.

import { fuzzyEqual, tokenize } from '@/lib/text';

/** How many upcoming page words one spoken word may match against. */
const LOOKAHEAD = 3;

/**
 * Walk the spoken words from page word `from`, matching each against the next
 * 1 to 3 page words. Returns the number of page words read so far.
 */
export function matchForward(expected: string[], spoken: string[], from = 0): number {
  let pos = from;
  for (const word of spoken) {
    if (pos >= expected.length) break;
    for (let k = 0; k < LOOKAHEAD && pos + k < expected.length; k++) {
      if (fuzzyEqual(word, expected[pos + k])) {
        pos += k + 1;
        break;
      }
    }
  }
  return pos;
}

export interface CursorState {
  /** Page words read so far; the current word is expected[cursor]. */
  cursor: number;
  /** Page word where the current partial transcript starts. */
  base: number;
  prevLen: number;
  prevFirst: string;
}

export const INITIAL_CURSOR: CursorState = { cursor: 0, base: 0, prevLen: 0, prevFirst: '' };

/**
 * Fold the latest live partial transcript into the cursor.
 * Works whether the listener reports one growing transcript or restarts its
 * partial after each committed segment: a partial that shrinks or changes its
 * first word is treated as a new segment that starts at the current cursor.
 */
export function advanceCursor(state: CursorState, expected: string[], partialText: string): CursorState {
  const spoken = tokenize(partialText);
  if (!spoken.length) return { ...state, base: state.cursor, prevLen: 0, prevFirst: '' };
  const restarted =
    state.prevLen > 0 && (spoken.length < state.prevLen - 1 || !fuzzyEqual(spoken[0], state.prevFirst));
  const base = restarted ? state.cursor : state.base;
  const reached = matchForward(expected, spoken, base);
  return { cursor: Math.max(state.cursor, reached), base, prevLen: spoken.length, prevFirst: spoken[0] };
}
