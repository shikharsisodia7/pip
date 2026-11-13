import { describe, expect, it } from 'vitest';
import { tokenizeDisplay } from '@/lib/text';
import { evenTimings, wordsFromAlignment, type CharAlignment } from './alignment';

function fakeAlignment(text: string, secPerChar = 0.05): CharAlignment {
  const characters = [...text];
  return {
    characters,
    character_start_times_seconds: characters.map((_, i) => i * secPerChar),
    character_end_times_seconds: characters.map((_, i) => (i + 1) * secPerChar),
  };
}

describe('wordsFromAlignment', () => {
  it('produces one timed word per page token, in order', () => {
    const text = 'Then a loud boom shook the trees.';
    const words = wordsFromAlignment(text, fakeAlignment(text));
    expect(words.map((w) => w.text)).toEqual(tokenizeDisplay(text).map((t) => t.display));
    for (let i = 1; i < words.length; i++) expect(words[i].start).toBeGreaterThan(words[i - 1].start);
  });

  it('uses the character times of each word', () => {
    const text = 'Oh no!';
    const words = wordsFromAlignment(text, fakeAlignment(text, 0.1));
    expect(words[0]).toEqual({ text: 'Oh', start: 0, end: 0.2 });
    expect(words[1]).toEqual({ text: 'no!', start: 0.3, end: 0.6 });
  });

  it('keeps indexes aligned with quotes and dashes', () => {
    const text = '"Oh no! What was that?" she cried, wide-eyed.';
    const words = wordsFromAlignment(text, fakeAlignment(text));
    expect(words).toHaveLength(tokenizeDisplay(text).length);
  });

  it('falls back to even timings without alignment', () => {
    const text = 'Did I get that right?';
    expect(wordsFromAlignment(text, null)).toEqual(evenTimings(text));
  });
});
