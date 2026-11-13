import { describe, expect, it } from 'vitest';
import { getDemoBook } from '@/lib/books';
import type { ExpressionResult, PipPlan, ProsodyStats } from '@/lib/types';
import { expressionView, mistakesView, patternsView, probeView, readingView, topPattern } from './derive';
import { buildSampleReport, isSample } from './sample';

const stats = (voicedFrames: number): ProsodyStats => ({
  pitchRangeSemitones: 8, pitchSdSemitones: 2, loudnessSdDb: 3, wordsPerSec: 1.5, voicedFrames,
});

const plan: PipPlan = {
  pageIndex: 1,
  sentences: [],
  mistakes: [
    { wordIndex: 3, sentenceIndex: 0, correct: 'shook', misread: 'sook', speakAs: 'sook', patternId: 'sh', reaction: '' },
    { wordIndex: 7, sentenceIndex: 1, correct: 'jumped', misread: 'jump-ed', speakAs: 'jump ed', patternId: 'ed', reaction: '' },
    { wordIndex: 12, sentenceIndex: 2, correct: 'what', misread: 'wat', speakAs: 'wat', patternId: 'wh', reaction: '' },
  ],
};

describe('readingView', () => {
  it('hides when metrics are missing or empty', () => {
    expect(readingView(undefined)).toBeNull();
    expect(readingView({ wcpm: 0, accuracyPct: 0, wordsCorrect: 0, wordsTotal: 0, durationSec: 0, hesitations: 0, selfCorrections: 0 })).toBeNull();
  });

  it('drops a words-per-minute figure that was not measured', () => {
    const v = readingView({ wcpm: NaN, accuracyPct: 88, wordsCorrect: 15, wordsTotal: 17, durationSec: 0, hesitations: 0, selfCorrections: 0 });
    expect(v).toMatchObject({ accuracyPct: 88, wordsTotal: 17, wordsCorrect: 15 });
    expect(v?.wcpm).toBeUndefined();
    expect(v?.durationSec).toBeUndefined();
  });
});

describe('mistakesView', () => {
  it('counts only the mistakes Pip actually read', () => {
    const v = mistakesView(plan, [
      { wordIndex: 3, caught: true, via: 'voice' },
      { wordIndex: 7, caught: false, via: 'missed' },
    ]);
    expect(v).toMatchObject({ caught: 1, total: 2 });
    expect(v?.rows.map((r) => r.outcome)).toEqual(['voice', 'missed']);
  });

  it('prefers a catch over an earlier miss on the same word', () => {
    const v = mistakesView(plan, [
      { wordIndex: 3, caught: false, via: 'missed' },
      { wordIndex: 3, caught: true, via: 'tap' },
    ]);
    expect(v).toMatchObject({ caught: 1, total: 1 });
    expect(v?.rows[0].outcome).toBe('tap');
  });

  it('hides when nothing was presented', () => {
    expect(mistakesView(plan, [])).toBeNull();
    expect(mistakesView(undefined, [{ wordIndex: 3, caught: true, via: 'voice' }])).toBeNull();
  });
});

describe('patternsView and topPattern', () => {
  const diagnosis = {
    kidMessage: '',
    patterns: [
      { id: 'ough', kidLabel: '', teacherLabel: 'vowel team: ough', evidenceWords: ['thought', 'thought'], confidence: 0.9 },
      { id: 'ough', kidLabel: '', teacherLabel: 'vowel team: ough', evidenceWords: [], confidence: 0.5 },
    ],
  };

  it('dedupes and uses teacher labels', () => {
    const mistakes = mistakesView(plan, [{ wordIndex: 7, caught: true, via: 'voice' }]);
    const v = patternsView(diagnosis, mistakes);
    expect(v?.needsPractice).toEqual([{ id: 'ough', teacherLabel: 'vowel team: ough', words: ['thought'] }]);
    expect(v?.practicedToday).toEqual([{ id: 'ed', teacherLabel: 'inflectional ending: -ed', words: ['jumped'] }]);
  });

  it('hides when there is nothing to show', () => {
    expect(patternsView(undefined, null)).toBeNull();
  });

  it('picks the top diagnosed pattern, else the first practiced one', () => {
    expect(topPattern(diagnosis, null)?.id).toBe('ough');
    const mistakes = mistakesView(plan, [{ wordIndex: 3, caught: true, via: 'voice' }]);
    expect(topPattern(undefined, mistakes)).toMatchObject({ id: 'sh', evidenceWords: ['shook'] });
    expect(topPattern(undefined, null)).toBeNull();
  });
});

describe('expressionView', () => {
  const result = (over: Partial<ExpressionResult>): ExpressionResult => ({
    baseline: stats(200), attempt: stats(80), score: 1.8, passed: true, attempts: 1, tags: [], ...over,
  });

  it('draws the attempt against the baseline on one scale', () => {
    const v = expressionView(result({}));
    expect(v?.passed).toBe(true);
    expect(v?.bars?.baseline).toBe(1);
    expect(v?.bars?.attempt).toBe(1.8);
    expect(v?.bars!.scale).toBeGreaterThanOrEqual(1.8);
  });

  it('drops the bars without a usable baseline', () => {
    expect(expressionView(result({ baseline: null }))?.bars).toBeNull();
    expect(expressionView(result({ baseline: stats(5) }))?.bars).toBeNull();
  });

  it('hides when there was no real attempt or the score is not a number', () => {
    expect(expressionView(undefined)).toBeNull();
    expect(expressionView(result({ attempt: stats(0), score: 0 }))).toBeNull();
    expect(expressionView(result({ score: NaN }))).toBeNull();
  });
});

describe('probeView', () => {
  const r = (flags: boolean[]) => ({
    items: flags.map((correct, i) => ({ word: `w${i}`, patternId: 'igh', correct })),
    correctCount: flags.filter(Boolean).length,
  });

  it('needs both checks', () => {
    expect(probeView(r([true]), undefined)).toBeNull();
    expect(probeView(undefined, r([true]))).toBeNull();
    expect(probeView(r([]), r([true]))).toBeNull();
  });

  it('counts from the items shown', () => {
    const v = probeView(r([true, true, false, false, false]), r([true, true, true, true, false]));
    expect(v?.before).toMatchObject({ correct: 2, total: 5 });
    expect(v?.after).toMatchObject({ correct: 4, total: 5 });
  });
});

describe('buildSampleReport', () => {
  const book = getDemoBook();
  const sample = buildSampleReport(book, 0, 1);

  it('fills every report section with finite numbers', () => {
    const reading = readingView(sample.read.metrics);
    expect(reading?.wcpm).toBeGreaterThan(0);
    expect(reading?.accuracyPct).toBeGreaterThan(0);
    const mistakes = mistakesView(sample.pipPlan, sample.catches);
    expect(mistakes?.total).toBeGreaterThan(0);
    expect(patternsView(sample.diagnosis, mistakes)?.needsPractice.length).toBeGreaterThan(0);
    expect(expressionView(sample.expression)?.bars).not.toBeNull();
    expect(probeView(sample.probePre, sample.probePost)).toMatchObject({ before: { correct: 2 }, after: { correct: 4 } });
  });

  it('plants mistakes on words from the page Pip reads', () => {
    const pipWords = book.pages[1].text.toLowerCase();
    for (const m of sample.pipPlan.mistakes) {
      expect(pipWords).toContain(m.correct);
      expect(m.misread).not.toBe(m.correct);
    }
  });

  it('marks every slice as sample data', () => {
    for (const slice of [sample.read, sample.diagnosis, sample.pipPlan, sample.catches, sample.expression, sample.probePre, sample.probePost]) {
      expect(isSample(slice)).toBe(true);
    }
    expect(isSample({ ...sample.read })).toBe(false);
  });
});
