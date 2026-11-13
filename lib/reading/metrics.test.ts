import { describe, expect, it } from 'vitest';
import type { AlignmentResult } from '@/lib/types';
import { alignWords } from './align';
import { computeMetrics } from './metrics';

describe('computeMetrics', () => {
  it('uses elapsed time from the first aligned start to the last end for WCPM', () => {
    const alignment = alignWords('The cat sat.', {
      text: 'The cap sat.',
      words: [
        { text: 'The', start: 5, end: 5.5 },
        { text: 'cap', start: 6, end: 6.5 },
        { text: 'sat', start: 7, end: 7.5 },
      ],
    });
    expect(computeMetrics(alignment)).toEqual({
      wcpm: 48, accuracyPct: 67, wordsCorrect: 2, wordsTotal: 3,
      durationSec: 2.5, hesitations: 0, selfCorrections: 0,
    });
  });

  it('includes corrected words in accuracy and WCPM while counting them separately', () => {
    const alignment: AlignmentResult = {
      words: [
        { index: 0, expected: 'the', status: 'correct', start: 0, end: 1 },
        { index: 1, expected: 'cat', status: 'selfCorrected', said: 'dog', start: 3, end: 4, hesitationBeforeSec: 1.5 },
        { index: 2, expected: 'sat', status: 'omission' },
      ],
      insertions: [{ afterIndex: 1, said: 'down' }],
    };
    expect(computeMetrics(alignment)).toEqual({
      wcpm: 30, accuracyPct: 67, wordsCorrect: 2, wordsTotal: 3,
      durationSec: 4, hesitations: 1, selfCorrections: 1,
    });
  });

  it('keeps a timed substitution at either boundary in the duration', () => {
    const alignment = alignWords('The cat sat.', {
      text: 'Red cat ran.',
      words: [
        { text: 'Red', start: 2, end: 3 },
        { text: 'cat', start: 3, end: 4 },
        { text: 'ran', start: 4, end: 8 },
      ],
    });
    expect(computeMetrics(alignment)).toMatchObject({ wordsCorrect: 1, durationSec: 6, wcpm: 10 });
  });

  it('returns zeros for an empty alignment', () => {
    expect(computeMetrics({ words: [], insertions: [] })).toEqual({
      wcpm: 0, accuracyPct: 0, wordsCorrect: 0, wordsTotal: 0,
      durationSec: 0, hesitations: 0, selfCorrections: 0,
    });
  });

  it('returns zero pace and accuracy when nothing was read', () => {
    const alignment = alignWords('The cat sat.', { text: '', words: [] });
    expect(computeMetrics(alignment)).toMatchObject({
      wcpm: 0, accuracyPct: 0, durationSec: 0, wordsTotal: 3, wordsCorrect: 0,
    });
  });

  it('guards zero duration without discarding correct words', () => {
    const alignment = alignWords('cat', { text: 'cat', words: [{ text: 'cat', start: 2, end: 2 }] });
    expect(computeMetrics(alignment)).toMatchObject({ wcpm: 0, durationSec: 0, accuracyPct: 100, wordsCorrect: 1 });
  });

  it('does not invent duration when timestamps are missing or invalid', () => {
    const alignment: AlignmentResult = {
      words: [
        { index: 0, expected: 'the', status: 'correct' },
        { index: 1, expected: 'cat', status: 'correct', start: 3, end: 2 },
        { index: 2, expected: 'sat', status: 'correct', start: NaN, end: Infinity },
      ],
      insertions: [],
    };
    expect(computeMetrics(alignment)).toMatchObject({ wcpm: 0, durationSec: 0, accuracyPct: 100 });
  });

  it('uses unrounded duration to calculate pace before rounding display values', () => {
    const alignment = alignWords('cat', { text: 'cat', words: [{ text: 'cat', start: 0, end: 0.334 }] });
    expect(computeMetrics(alignment)).toMatchObject({ durationSec: 0.33, wcpm: 180 });
  });

  it('counts only hesitation gaps exceeding the threshold', () => {
    const alignment: AlignmentResult = {
      words: [
        { index: 0, expected: 'the', status: 'correct', hesitationBeforeSec: 0.8 },
        { index: 1, expected: 'cat', status: 'correct', hesitationBeforeSec: 1.2 },
        { index: 2, expected: 'sat', status: 'correct', hesitationBeforeSec: 2 },
      ],
      insertions: [],
    };
    expect(computeMetrics(alignment).hesitations).toBe(2);
  });
});
