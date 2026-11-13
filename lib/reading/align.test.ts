import { describe, expect, it } from 'vitest';
import demoTranscript from '@/fixtures/transcripts/page1-demo.json';
import { getDemoBook } from '@/lib/books';
import { fuzzyEqual, normalizeToken, tokenizeDisplay } from '@/lib/text';
import type { Transcript } from '@/lib/types';
import { alignWords } from './align';
import { computeMetrics } from './metrics';

function transcript(text: string): Transcript {
  return {
    text,
    words: text.split(/\s+/).filter(Boolean).map((word, index) => ({
      text: word, start: index, end: index + 0.5,
    })),
  };
}

describe('alignWords', () => {
  it('aligns a perfect read with page indexes and transcript timestamps', () => {
    expect(alignWords('The cat sat.', transcript('The cat sat.'))).toEqual({
      words: [
        { index: 0, expected: 'the', status: 'correct', start: 0, end: 0.5 },
        { index: 1, expected: 'cat', status: 'correct', start: 1, end: 1.5 },
        { index: 2, expected: 'sat', status: 'correct', start: 2, end: 2.5 },
      ],
      insertions: [],
    });
  });

  it('records a normalized substitution without shifting later words', () => {
    const result = alignWords('The cat sat.', transcript('The CAP, sat.'));
    expect(result.words.map((word) => word.status)).toEqual(['correct', 'substitution', 'correct']);
    expect(result.words[1]).toMatchObject({ index: 1, expected: 'cat', said: 'cap', start: 1, end: 1.5 });
    expect(result.insertions).toEqual([]);
  });

  it('marks an omission without borrowing the next word or its timestamps', () => {
    const result = alignWords('The little cat sat.', transcript('The cat sat.'));
    expect(result.words[1]).toEqual({ index: 1, expected: 'little', status: 'omission' });
    expect(result.words[2]).toMatchObject({ index: 2, status: 'correct', start: 1 });
    expect(result.words[3].status).toBe('correct');
  });

  it('records an extra spoken word after the final page word', () => {
    const result = alignWords('The cat sat.', transcript('The cat sat down.'));
    expect(result.words.every((word) => word.status === 'correct')).toBe(true);
    expect(result.insertions).toEqual([{ afterIndex: 2, said: 'down' }]);
  });

  it('recognizes an immediate self-correction and times the corrected word', () => {
    const result = alignWords('The cat sat.', transcript('The dog cat sat.'));
    expect(result.words[1]).toEqual({
      index: 1, expected: 'cat', status: 'selfCorrected', said: 'dog', start: 2, end: 2.5,
    });
    expect(result.words[2].status).toBe('correct');
    expect(result.insertions).toEqual([]);
    expect(computeMetrics(result)).toMatchObject({ accuracyPct: 100, wordsCorrect: 3, selfCorrections: 1 });
  });

  it.each(['br-', 'brigh-'])('recognizes the false start %s before the right word', (attempt) => {
    const result = alignWords('A bright moon.', transcript(`A ${attempt} bright moon.`));
    expect(result.words[1]).toMatchObject({ status: 'selfCorrected', said: normalizeToken(attempt), start: 2 });
    expect(result.insertions).toEqual([]);
  });

  it('does not count repeated correct words as errors or self-corrections', () => {
    const result = alignWords('The cat sat.', transcript('The the the cat cat sat sat.'));
    expect(result.words.map((word) => word.status)).toEqual(['correct', 'correct', 'correct']);
    expect(result.words.map((word) => word.start)).toEqual([0, 3, 5]);
    expect(result.insertions).toEqual([]);
  });

  it('keeps repeated words that really occur on the page', () => {
    const result = alignWords('A very very quiet night.', transcript('A very very very quiet night.'));
    expect(result.words).toHaveLength(5);
    expect(result.words.every((word) => word.status === 'correct')).toBe(true);
    expect(result.insertions).toEqual([]);
  });

  it('keeps a self-correction when the corrected word is then repeated', () => {
    const result = alignWords('The cat sat.', transcript('The dog cat cat cat sat.'));
    expect(result.words.map((word) => word.status)).toEqual(['correct', 'selfCorrected', 'correct']);
    expect(result.words[1].start).toBe(2);
    expect(result.insertions).toEqual([]);
  });

  it('marks a gap longer than 0.8 seconds before a spoken word', () => {
    const result = alignWords('The cat.', {
      text: 'The cat.',
      words: [{ text: 'The', start: 10, end: 10.5 }, { text: 'cat', start: 12, end: 12.5 }],
    });
    expect(result.words[0].hesitationBeforeSec).toBeUndefined();
    expect(result.words[1].hesitationBeforeSec).toBe(1.5);
  });

  it('does not mark exactly 0.8 seconds as a hesitation', () => {
    const result = alignWords('The cat.', {
      text: 'The cat.',
      words: [{ text: 'The', start: 0, end: 0.4 }, { text: 'cat', start: 1.2, end: 1.5 }],
    });
    expect(result.words[1].hesitationBeforeSec).toBeUndefined();
  });

  it('measures hesitation from the previous spoken word, including repeats', () => {
    const result = alignWords('The cat.', {
      text: 'The the cat.',
      words: [
        { text: 'The', start: 0, end: 0.2 },
        { text: 'the', start: 0.3, end: 0.9 },
        { text: 'cat', start: 1.2, end: 1.5 },
      ],
    });
    expect(result.words[1].hesitationBeforeSec).toBeUndefined();
  });

  it('measures a correction gap from the incorrect attempt', () => {
    const result = alignWords('cat', {
      text: 'dog cat',
      words: [{ text: 'dog', start: 0, end: 0.5 }, { text: 'cat', start: 2, end: 2.5 }],
    });
    expect(result.words[0]).toMatchObject({ status: 'selfCorrected', hesitationBeforeSec: 1.5 });
  });

  it('matches contractions with curly, straight, or missing apostrophes', () => {
    const result = alignWords('Don’t worry, it’s quiet.', transcript("dont worry it's quiet"));
    expect(result.words.map((word) => word.expected)).toEqual(["don't", 'worry', "it's", 'quiet']);
    expect(result.words.every((word) => word.status === 'correct')).toBe(true);
  });

  it('uses display token indexes despite punctuation and ignores punctuation-only speech tokens', () => {
    const result = alignWords('"Look!" ... A cat, ran.', transcript('LOOK ... a cat ran!'));
    expect(result.words.map((word) => [word.index, word.expected])).toEqual([
      [0, 'look'], [1, 'a'], [2, 'cat'], [3, 'ran'],
    ]);
    expect(result.words.every((word) => word.status === 'correct')).toBe(true);
    expect(result.insertions).toEqual([]);
  });

  it('normalizes numbers in both page and spoken words', () => {
    const result = alignWords('2 cats saw three birds.', transcript('two cats saw 3 birds'));
    expect(result.words.map((word) => word.expected)).toEqual(['two', 'cats', 'saw', 'three', 'birds']);
    expect(result.words.every((word) => word.status === 'correct')).toBe(true);
  });

  it('uses the shared fuzzy rule without forgiving short-word substitutions', () => {
    const result = alignWords('A bright cat.', transcript('A brigt cap.'));
    expect(result.words.map((word) => word.status)).toEqual(['correct', 'correct', 'substitution']);
  });

  it('marks every expected word omitted for an empty transcript', () => {
    const result = alignWords('The cat.', transcript(''));
    expect(result).toEqual({
      words: [
        { index: 0, expected: 'the', status: 'omission' },
        { index: 1, expected: 'cat', status: 'omission' },
      ],
      insertions: [],
    });
  });

  it('keeps insertions in order when the transcript is longer than the page', () => {
    const result = alignWords('The cat.', transcript('The cat ran past the dog.'));
    expect(result.words.every((word) => word.status === 'correct')).toBe(true);
    expect(result.insertions).toEqual(['ran', 'past', 'the', 'dog'].map((said) => ({ afterIndex: 1, said })));
  });

  it('records words before an empty page using afterIndex -1', () => {
    expect(alignWords('', transcript('hello owl'))).toEqual({
      words: [], insertions: [{ afterIndex: -1, said: 'hello' }, { afterIndex: -1, said: 'owl' }],
    });
    expect(alignWords('', transcript(''))).toEqual({ words: [], insertions: [] });
  });

  it('classifies an entirely wrong read as substitutions', () => {
    const result = alignWords('The cat sat.', transcript('Red dog ran.'));
    expect(result.words.map((word) => word.status)).toEqual(['substitution', 'substitution', 'substitution']);
    expect(result.words.map((word) => word.said)).toEqual(['red', 'dog', 'ran']);
    expect(result.insertions).toEqual([]);
  });

  it('preserves distinct expected occurrences when a wrong word precedes a repeated page word', () => {
    const result = alignWords('cat cat', transcript('dog cat'));
    expect(result.words.map((word) => word.status)).toEqual(['substitution', 'correct']);
  });

  it('detects staged substitutions in the sample demo transcript without depending on its story', () => {
    const pageText = getDemoBook().pages[0].text;
    const result = alignWords(pageText, demoTranscript);
    expect(result.words.map((word) => word.expected)).toEqual(tokenizeDisplay(pageText).map((word) => word.norm));
    expect(result.words.map((word) => word.index)).toEqual(result.words.map((_, index) => index));
    const substitutions = result.words.filter((word) => word.status === 'substitution');
    expect(substitutions.length).toBeGreaterThan(0);
    for (const word of substitutions) {
      expect(fuzzyEqual(word.expected, word.said!)).toBe(false);
      expect(demoTranscript.words.some((said) => normalizeToken(said.text) === word.said)).toBe(true);
    }
    const metrics = computeMetrics(result);
    expect(metrics.wordsCorrect).toBeGreaterThan(0);
    expect(metrics.accuracyPct).toBeLessThan(100);
    expect(metrics.durationSec).toBeGreaterThan(0);
    expect(metrics.wcpm).toBeGreaterThan(0);
  });
});
