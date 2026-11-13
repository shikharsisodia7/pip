import { afterEach, describe, expect, it, vi } from 'vitest';
import * as books from '@/lib/books';
import { PATTERNS, getPattern } from '@/lib/patterns';
import { tokenize } from '@/lib/text';
import type { PatternFinding } from '@/lib/types';
import { PROBE_WORD_BANK } from './bank';
import { pickProbeWords } from './index';

const originalBook = books.getDemoBook();

function finding(id: string, confidence = 0.9): PatternFinding {
  const pattern = getPattern(id);
  return {
    id,
    confidence,
    evidenceWords: [],
    kidLabel: pattern?.kidLabel ?? id,
    teacherLabel: pattern?.teacherLabel ?? id,
  };
}

function replaceBookText(text: string) {
  vi.spyOn(books, 'getDemoBook').mockReturnValue({
    ...originalBook,
    title: 'Sample book',
    pages: [{ index: 0, text, scene: { emoji: '', bg: '' } }],
  });
}

afterEach(() => vi.restoreAllMocks());

describe('probe word bank', () => {
  it('covers exactly the shared taxonomy', () => {
    expect(Object.keys(PROBE_WORD_BANK).sort()).toEqual(PATTERNS.map((pattern) => pattern.id).sort());
  });

  it.each(PATTERNS)('has at least eight distinct valid words for $id', (pattern) => {
    const words = PROBE_WORD_BANK[pattern.id];
    expect(new Set(words).size).toBe(words.length);
    expect(words.length).toBeGreaterThanOrEqual(8);
    for (const word of words) {
      expect(tokenize(word)).toEqual([word]);
      expect(pattern.test(word), `${word} must match ${pattern.id}`).toBe(true);
    }
  });
});

describe('pickProbeWords', () => {
  it('uses five fixed words from five different patterns before reading', () => {
    replaceBookText('');
    const pre = pickProbeWords('pre');
    expect(pre.map((item) => item.word)).toEqual(['rain', 'boat', 'fish', 'kite', 'light']);
    expect(new Set(pre.map((item) => item.patternId)).size).toBe(5);
    expect(pickProbeWords('pre', [finding('ough')])).toEqual(pre);
  });

  it('revisits all five patterns with different words when there are no findings', () => {
    const pre = pickProbeWords('pre');
    const post = pickProbeWords('post');
    expect(post.map((item) => item.patternId)).toEqual(pre.map((item) => item.patternId));
    expect(new Set([...pre, ...post].map((item) => item.word)).size).toBe(10);
    expect(pickProbeWords('post')).toEqual(post);
  });

  it('weights the strongest two findings without mutating the findings', () => {
    const findings = [finding('ed', 0.6), finding('ea', 0.95), finding('ou', 0.8)];
    const post = pickProbeWords('post', findings);
    expect(post.map((item) => item.patternId)).toEqual(['ea', 'ea', 'ea', 'ou', 'ou']);
    expect(findings.map((item) => item.id)).toEqual(['ed', 'ea', 'ou']);
  });

  it.each(PATTERNS)('can target $id without repeating either probe or the book', (pattern) => {
    const pre = pickProbeWords('pre');
    const post = pickProbeWords('post', [finding(pattern.id)]);
    const storyWords = new Set(tokenize(originalBook.pages.map((page) => page.text).join(' ')));
    expect(post).toHaveLength(5);
    expect(post.every((item) => item.patternId === pattern.id)).toBe(true);
    expect(new Set([...pre, ...post].map((item) => item.word)).size).toBe(10);
    for (const item of [...pre, ...post]) {
      expect(storyWords.has(item.word)).toBe(false);
      expect(getPattern(item.patternId)?.test(item.word)).toBe(true);
    }
  });

  it('ignores unknown findings and deduplicates repeated pattern ids', () => {
    expect(pickProbeWords('post', [finding('unknown')])).toEqual(pickProbeWords('post'));
    const post = pickProbeWords('post', [finding('ea', 1), finding('ea', 0.9), finding('ed', 0.8)]);
    expect(post.map((item) => item.patternId)).toEqual(['ea', 'ea', 'ea', 'ed', 'ed']);
  });

  it('replaces words at runtime when the demo book changes', () => {
    const previous = [...pickProbeWords('pre'), ...pickProbeWords('post')];
    const blocked = previous.map((item) => item.word);
    replaceBookText(blocked.map((word) => `“${word.toUpperCase()}!”`).join(' '));
    const pre = pickProbeWords('pre');
    const post = pickProbeWords('post', [finding('ai'), finding('oa')]);
    expect(pre).toHaveLength(5);
    expect(post).toHaveLength(5);
    expect(new Set(pre.map((item) => item.patternId)).size).toBe(5);
    expect(new Set([...pre, ...post].map((item) => item.word)).size).toBe(10);
    expect([...pre, ...post].every((item) => !blocked.includes(item.word))).toBe(true);
  });

  it('excludes words in the title and emotion lines as well as every page', () => {
    vi.spyOn(books, 'getDemoBook').mockReturnValue({
      ...originalBook,
      title: 'Rain',
      pages: [
        { index: 0, text: 'boat', scene: { emoji: '', bg: '' } },
        { index: 1, text: 'fish', scene: { emoji: '', bg: '' }, emotionLine: { text: 'kite light', emotion: 'happy' } },
      ],
    });
    const blocked = ['rain', 'boat', 'fish', 'kite', 'light'];
    expect([...pickProbeWords('pre'), ...pickProbeWords('post')].every((item) => !blocked.includes(item.word))).toBe(true);
  });

  it('keeps five distinct pre patterns and five post words when a bank is exhausted', () => {
    replaceBookText([...PROBE_WORD_BANK.ai, ...PROBE_WORD_BANK.oa].join(' '));
    const pre = pickProbeWords('pre');
    const post = pickProbeWords('post', [finding('ai'), finding('oa')]);
    expect(new Set(pre.map((item) => item.patternId)).size).toBe(5);
    expect(post).toHaveLength(5);
    expect(new Set([...pre, ...post].map((item) => item.word)).size).toBe(10);
    expect([...pre, ...post].some((item) => ['ai', 'oa'].includes(item.patternId))).toBe(false);
  });
});
