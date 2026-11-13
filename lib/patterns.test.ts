import { describe, expect, it } from 'vitest';
import { getPattern, hardestPatternIn, PATTERNS, patternsForWord, wordsWithPattern } from './patterns';

const ids = (word: string) => patternsForWord(word).map((p) => p.id);

describe('taxonomy', () => {
  it('has unique ids and is ordered hardest first', () => {
    expect(new Set(PATTERNS.map((p) => p.id)).size).toBe(PATTERNS.length);
    for (let i = 1; i < PATTERNS.length; i++) {
      expect(PATTERNS[i - 1].difficulty).toBeGreaterThanOrEqual(PATTERNS[i].difficulty);
    }
  });
  it('covers the required patterns', () => {
    for (const id of ['ough', 'ou', 'ea', 'ai', 'oa', 'ed', 'silent-e', 'th', 'sh', 'ch', 'wh', 'igh', 'ar', 'or', 'er']) {
      expect(getPattern(id), id).toBeDefined();
    }
  });
});

describe('pattern tests', () => {
  it('detects ough and th in thought', () => {
    expect(ids('thought')).toEqual(expect.arrayContaining(['ough', 'th']));
    expect(ids('thought')).not.toContain('ou');
  });
  it('detects -ed endings but not short -ed words', () => {
    expect(ids('jumped')).toContain('ed');
    expect(ids('red')).not.toContain('ed');
    expect(ids('need')).not.toContain('ed');
  });
  it('detects silent e', () => {
    expect(ids('smile')).toContain('silent-e');
    expect(ids('have')).not.toContain('silent-e');
    expect(ids('house')).not.toContain('silent-e');
  });
  it('detects igh', () => {
    expect(ids('Bright!')).toContain('igh');
  });
});

describe('wordsWithPattern', () => {
  it('returns page word indexes', () => {
    expect(wordsWithPattern('The night was bright.', 'igh')).toEqual([
      { index: 1, word: 'night', display: 'night' },
      { index: 3, word: 'bright', display: 'bright.' },
    ]);
  });
  it('returns nothing for an unknown id', () => {
    expect(wordsWithPattern('anything', 'nope')).toEqual([]);
  });
});

describe('hardestPatternIn', () => {
  it('picks the hardest pattern present', () => {
    expect(hardestPatternIn('She thought about the night')?.id).toBe('ough');
  });
});
