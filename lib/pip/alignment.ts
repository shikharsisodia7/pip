// Converts ElevenLabs character-level alignment into word timings.
//
// Word i in the result is token i of tokenizeDisplay(text), the same word indexing
// used everywhere else in the app, so highlighting lines up with the page.

import { tokenizeDisplay } from '@/lib/text';
import type { TimedWord } from '@/lib/types';

export interface CharAlignment {
  characters: string[];
  character_start_times_seconds: number[];
  character_end_times_seconds: number[];
}

const round = (n: number) => Math.round(n * 1000) / 1000;

/** Evenly spaced fake timings, used for placeholders and as a fallback. */
export function evenTimings(text: string, secPerWord = 0.42): TimedWord[] {
  return tokenizeDisplay(text).map((t, i) => ({
    text: t.display,
    start: round(i * secPerWord),
    end: round(i * secPerWord + secPerWord * 0.8),
  }));
}

export function wordsFromAlignment(text: string, alignment: CharAlignment | null | undefined): TimedWord[] {
  const tokens = tokenizeDisplay(text);
  if (!alignment || !alignment.characters?.length) return evenTimings(text);

  const chars = alignment.characters;
  const starts = alignment.character_start_times_seconds;
  const ends = alignment.character_end_times_seconds;
  const aligned = chars.join('');
  const total = ends[ends.length - 1] ?? 0;

  const words: TimedWord[] = [];
  let cursor = 0;
  for (let i = 0; i < tokens.length; i++) {
    const display = tokens[i].display;
    let at = aligned.indexOf(display, cursor);
    let len = display.length;
    if (at < 0) {
      // Dash handling in tokenizeDisplay can change spacing; fall back to the
      // first run of letters in the token.
      const core = display.match(/[A-Za-z0-9']+/)?.[0] ?? '';
      at = core ? aligned.indexOf(core, cursor) : -1;
      len = core.length;
    }
    if (at < 0 || len === 0) {
      // Proportional estimate so we never return a broken timeline.
      const frac = tokens.length ? i / tokens.length : 0;
      const start = round(total * frac);
      words.push({ text: display, start, end: round(Math.max(start, total * ((i + 1) / tokens.length))) });
      continue;
    }
    const last = Math.min(at + len - 1, chars.length - 1);
    words.push({ text: display, start: round(starts[at] ?? 0), end: round(ends[last] ?? starts[at] ?? 0) });
    cursor = at + len;
  }
  return words;
}
