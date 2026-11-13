import { describe, expect, it } from 'vitest';
import { editDistance, fuzzyEqual, normalizeToken, tokenize, tokenizeDisplay } from './text';

describe('normalizeToken', () => {
  it('lowercases and strips edge punctuation', () => {
    expect(normalizeToken('Quiet.')).toBe('quiet');
    expect(normalizeToken('"Oh')).toBe('oh');
  });
  it('keeps inner apostrophes and straightens curly ones', () => {
    expect(normalizeToken('Don’t')).toBe("don't");
  });
  it('spells out small numbers', () => {
    expect(normalizeToken('3')).toBe('three');
  });
});

describe('tokenize', () => {
  it('keeps display and normalized indexes aligned', () => {
    const t = tokenizeDisplay('She said, "Oh no!" — and ran.');
    expect(t.map((x) => x.norm)).toEqual(['she', 'said', 'oh', 'no', 'and', 'ran']);
    expect(t[2].display).toBe('"Oh');
  });
  it('splits words joined by an em dash', () => {
    expect(tokenize('Pip—the owl')).toEqual(['pip', 'the', 'owl']);
  });
});

describe('editDistance', () => {
  it('computes Levenshtein distance', () => {
    expect(editDistance('kitten', 'sitting')).toBe(3);
    expect(editDistance('', 'abc')).toBe(3);
    expect(editDistance('same', 'same')).toBe(0);
  });
});

describe('fuzzyEqual', () => {
  it('matches exact words regardless of case and punctuation', () => {
    expect(fuzzyEqual('Thought,', 'thought')).toBe(true);
  });
  it('forgives one edit on long words', () => {
    expect(fuzzyEqual('thought', 'thougt')).toBe(true);
  });
  it('keeps short-word substitutions as errors', () => {
    expect(fuzzyEqual('cat', 'cap')).toBe(false);
    expect(fuzzyEqual('look', 'looked')).toBe(false);
  });
  it('ignores apostrophes', () => {
    expect(fuzzyEqual("don't", 'dont')).toBe(true);
  });
  it('never matches empty words', () => {
    expect(fuzzyEqual('', '')).toBe(false);
  });
});
