import { afterEach, describe, expect, it, vi } from 'vitest';
import * as reading from '@/lib/reading/align';
import { transcriptFromText } from '@/lib/scribe/mock';
import { pickProbeWords } from './index';
import { scoreProbe } from './score';

afterEach(() => vi.restoreAllMocks());

describe('scoreProbe', () => {
  const items = pickProbeWords('pre');

  it('scores a single transcript against all five cards', () => {
    const transcript = transcriptFromText(items.map((item) => item.word).join(' '));
    const align = vi.spyOn(reading, 'alignWords');
    expect(scoreProbe(items, transcript)).toMatchObject({
      items: items.map((item) => ({ ...item, correct: true })),
      correctCount: 5,
    });
    expect(align).toHaveBeenCalledExactlyOnceWith(items.map((item) => item.word).join(' '), transcript);
  });

  it('retains substitutions and counts omitted cards as incorrect', () => {
    vi.spyOn(reading, 'alignWords').mockReturnValue({
      words: items.map((item, index) => ({
        index,
        expected: item.word,
        status: index === 0 ? 'correct' : index === 1 ? 'substitution' : 'omission',
        ...(index === 1 ? { said: 'zebra' } : {}),
      })),
      insertions: [],
    });
    const result = scoreProbe(items, transcriptFromText(`${items[0].word} zebra`));
    expect(result.correctCount).toBe(1);
    expect(result.items[1]).toMatchObject({ correct: false, said: 'zebra' });
    expect(result.items.slice(2).every((item) => !item.correct)).toBe(true);
    expect(result.items).toHaveLength(5);
  });

  it('counts self-corrections as correct and keeps the shared page indexes', () => {
    vi.spyOn(reading, 'alignWords').mockReturnValue({
      words: [
        { index: 3, expected: items[3].word, status: 'selfCorrected', said: items[3].word },
        { index: 1, expected: items[1].word, status: 'correct' },
        { index: 0, expected: items[0].word, status: 'substitution', said: 'zebra' },
        { index: 2, expected: items[2].word, status: 'omission' },
        { index: 4, expected: items[4].word, status: 'omission' },
      ],
      insertions: [{ afterIndex: 0, said: 'um' }],
    });
    const result = scoreProbe(items, transcriptFromText(''));
    expect(result.correctCount).toBe(2);
    expect(result.items.map((item) => item.correct)).toEqual([false, true, false, true, false]);
  });
});
