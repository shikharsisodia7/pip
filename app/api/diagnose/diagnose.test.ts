import { describe, expect, it } from 'vitest';
import fixture from '@/fixtures/claude/diagnose-demo.json';
import { getPattern } from '@/lib/patterns';
import { tokenize } from '@/lib/text';
import type { AlignmentResult, PatternFinding } from '@/lib/types';
import { buildDiagnosisContext, diagnoseResponseSchema, fallbackDiagnosis, validateDiagnosis } from './diagnose';

function omissions(pageText: string): AlignmentResult {
  return {
    words: tokenize(pageText).map((expected, index) => ({ index, expected, status: 'omission' })),
    insertions: [],
  };
}

function finding(id: string, evidenceWords: string[]): PatternFinding {
  return { id, kidLabel: 'Model label', teacherLabel: 'Model label', evidenceWords, confidence: 0.7 };
}

const samplePage = 'She looked at the moon.';
const sampleContext = buildDiagnosisContext(samplePage, {
  words: [{ index: 1, expected: 'looked', status: 'substitution', said: 'look' }],
  insertions: [],
});

describe('deterministic candidates', () => {
  it('includes substitutions, omissions, and hesitations, counting each word once', () => {
    const context = buildDiagnosisContext('looked jumped bright thought smile rain', {
      words: [
        { index: 0, expected: 'Looked!', status: 'substitution', said: 'look', hesitationBeforeSec: 1.2 },
        { index: 1, expected: 'jumped', status: 'omission' },
        { index: 2, expected: 'bright', status: 'correct', hesitationBeforeSec: 0.9 },
        { index: 3, expected: 'thought', status: 'correct', hesitationBeforeSec: 0.8 },
        { index: 4, expected: 'smile', status: 'selfCorrected' },
        { index: 5, expected: 'rain', status: 'selfCorrected', hesitationBeforeSec: 1 },
      ],
      insertions: [{ afterIndex: 3, said: 'boat' }],
    });
    expect(context.miscues.map((word) => word.index)).toEqual([0, 1, 2, 5]);
    expect(context.miscues[0]).toMatchObject({ said: 'look', candidatePatternIds: ['ed', 'oo'] });
    expect(context.candidates.map(({ id, count }) => ({ id, count }))).toEqual([
      { id: 'ed', count: 2 }, { id: 'igh', count: 1 }, { id: 'ai', count: 1 }, { id: 'oo', count: 1 },
    ]);
  });

  it('counts repeated words separately but keeps evidence unique', () => {
    const context = buildDiagnosisContext('looked looked', omissions('looked looked'));
    expect(context.candidates[0]).toMatchObject({ id: 'ed', count: 2, evidenceWords: ['looked'] });
  });

  it('ignores duplicate indexes and words that do not match their page position', () => {
    const context = buildDiagnosisContext('looked', {
      words: [
        { index: 0, expected: 'looked', status: 'omission' },
        { index: 0, expected: 'looked', status: 'substitution', said: 'look' },
        { index: 0, expected: 'thought', status: 'omission' },
        { index: 8, expected: 'thought', status: 'omission' },
      ],
      insertions: [],
    });
    expect(context.miscues).toHaveLength(1);
    expect(context.candidates[0].count).toBe(1);
  });
});

describe('deterministic fallback', () => {
  it('ranks frequency before difficulty and returns at most three patterns', () => {
    const page = 'thought jumped looked night';
    const response = fallbackDiagnosis(page, buildDiagnosisContext(page, omissions(page)));
    expect(response.patterns.map((pattern) => pattern.id)).toEqual(['ed', 'ough', 'igh']);
    expect(response.patterns[0]).toMatchObject({
      kidLabel: getPattern('ed')!.kidLabel,
      teacherLabel: getPattern('ed')!.teacherLabel,
      evidenceWords: ['jumped', 'looked'],
    });
    expect(response.kidMessage).toMatch(/^Pip noticed/);
    expect(response.kidMessage).not.toContain('\u2014');
  });

  it('uses taxonomy order when frequency and difficulty tie', () => {
    const page = 'boat rain';
    expect(fallbackDiagnosis(page, buildDiagnosisContext(page, omissions(page))).patterns.map((p) => p.id))
      .toEqual(['ai', 'oa']);
  });

  it('praises a clean read and selects the hardest page pattern at low confidence', () => {
    const page = 'She thought about the bright moon.';
    const alignment: AlignmentResult = {
      words: tokenize(page).map((expected, index) => ({ index, expected, status: 'correct' })),
      insertions: [],
    };
    const response = fallbackDiagnosis(page, buildDiagnosisContext(page, alignment));
    expect(response.patterns).toHaveLength(1);
    expect(response.patterns[0]).toMatchObject({ id: 'ough', evidenceWords: ['thought'] });
    expect(response.patterns[0].confidence).toBeLessThanOrEqual(0.3);
    expect(response.kidMessage).toContain('lovely reading');
  });

  it.each(['', 'cat sat'])('returns no invented pattern for a page without taxonomy matches: %j', (page) => {
    expect(fallbackDiagnosis(page, buildDiagnosisContext(page, omissions(page))).patterns).toEqual([]);
  });
});

describe('Claude response validation', () => {
  it('overwrites model labels and normalizes, deduplicates, and grounds evidence', () => {
    const response = validateDiagnosis({
      patterns: [finding('ed', ['LOOKED!', 'looked', 'jumped', 'look', 'moon'])],
      kidMessage: 'Pip noticed an ending to explore. Can you help Pip?',
    }, sampleContext);
    expect(response?.patterns).toEqual([{
      ...finding('ed', ['looked']),
      kidLabel: getPattern('ed')!.kidLabel,
      teacherLabel: getPattern('ed')!.teacherLabel,
    }]);
    expect(response?.kidMessage).toBe('Pip noticed an ending to explore. Can you help Pip?');
  });

  it('keeps valid findings while dropping unknown, unrelated, duplicate, and malformed findings', () => {
    const response = validateDiagnosis({
      patterns: [
        finding('invented', ['looked']),
        finding('sh', ['she']),
        finding('ed', ['jumped']),
        { ...finding('oo', ['looked']), confidence: 2 },
        null,
        finding('ed', ['looked']),
        finding('ed', ['looked']),
        finding('oo', ['looked']),
      ],
      kidMessage: 'Pip noticed some sounds to practice together!',
    }, sampleContext);
    expect(response?.patterns.map((pattern) => pattern.id)).toEqual(['ed', 'oo']);
  });

  it.each([-1, 1.1, NaN, Infinity, '0.8'])('rejects invalid confidence %s', (confidence) => {
    expect(validateDiagnosis({
      patterns: [{ ...finding('ed', ['looked']), confidence }], kidMessage: fixture.kidMessage,
    }, sampleContext)).toBeNull();
  });

  it.each([undefined, null, {}, { patterns: [] }, { patterns: [finding('ed', ['jumped'])] }])
    ('requests fallback when nothing valid remains: %j', (value) => {
      expect(validateDiagnosis(value, sampleContext)).toBeNull();
    });

  it('limits valid findings to three while preserving Claude ranking', () => {
    const page = 'thought night jumped boat';
    const response = validateDiagnosis({
      patterns: [finding('oa', ['boat']), finding('ed', ['jumped']), finding('igh', ['night']), finding('ough', ['thought'])],
      kidMessage: fixture.kidMessage,
    }, buildDiagnosisContext(page, omissions(page)));
    expect(response?.patterns.map((pattern) => pattern.id)).toEqual(['oa', 'ed', 'igh']);
  });

  it.each([
    undefined,
    'Try harder.',
    'Pip noticed a score of ninety.',
    'Pip noticed your grade is A.',
    'Pip noticed 90% accuracy.',
    'Pip noticed your reading\u2014well done!',
    `Pip noticed ${'a'.repeat(160)}`,
  ])('replaces unsuitable kid copy: %s', (kidMessage) => {
    const response = validateDiagnosis({ patterns: [finding('ed', ['looked'])], kidMessage }, sampleContext);
    expect(response?.patterns).toHaveLength(1);
    expect(response?.kidMessage).toBe(fallbackDiagnosis(samplePage, sampleContext).kidMessage);
  });

  it('accepts the sample fixture for looked read as look', () => {
    expect(diagnoseResponseSchema.parse(fixture)).toEqual(fixture);
    expect(validateDiagnosis(fixture, sampleContext)).toEqual(fixture);
  });
});
