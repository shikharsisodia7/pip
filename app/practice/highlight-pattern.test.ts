import { describe, expect, it } from 'vitest';
import { PATTERNS } from '@/lib/patterns';
import { highlightPattern } from './highlight-pattern';

const bold = (word: string, id: string) => highlightPattern(word, id).filter((part) => part.bold).map((part) => part.text);

describe('practice pattern letters', () => {
  it.each([
    ['Thought,', 'ough', ['ough']],
    ['NIGHT!', 'igh', ['IGH']],
    ['“jumped.”', 'ed', ['ed']],
    ['“smile.”', 'silent-e', ['i', 'e']],
    ['beach', 'ea', ['ea']],
    ['“sound!”', 'ou', ['ou']],
    ['birthday', 'er', ['ir']],
    ['play', 'ai', ['ay']],
    ['boy', 'oi', ['oy']],
    ['teacup', 'ea', ['ea']],
  ])('highlights only target letters in %s for %s', (word, id, expected) => {
    expect(bold(word, id)).toEqual(expected);
    expect(highlightPattern(word, id).map((part) => part.text).join('')).toBe(word);
  });

  it.each([
    ['red', 'ed'], ['need', 'ed'], ['love', 'silent-e'], ['have', 'silent-e'],
    ['thought', 'ou'], ['could', 'ou'], ['you', 'ou'], ['night', 'unknown'],
  ])('does not highlight %s for %s', (word, id) => {
    expect(bold(word, id)).toEqual([]);
  });

  it.each(PATTERNS)('shows a pattern in the $id example', (pattern) => {
    expect(bold(pattern.example, pattern.id).length).toBeGreaterThan(0);
  });
});
