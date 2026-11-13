import { describe, expect, it } from 'vitest';
import { extractSummary } from './summary';

describe('extractSummary', () => {
  it('returns the summary line, trimmed', () => {
    expect(extractSummary({ precision: 0.8, summary: '  When Pip flags a word, experts agreed. ' }))
      .toBe('When Pip flags a word, experts agreed.');
  });

  it('accepts slideLine as an alias', () => {
    expect(extractSummary({ slideLine: 'One line.' })).toBe('One line.');
  });

  it('returns null when there is no usable line', () => {
    expect(extractSummary(null)).toBeNull();
    expect(extractSummary('text')).toBeNull();
    expect(extractSummary({ precision: 0.8 })).toBeNull();
    expect(extractSummary({ summary: '   ' })).toBeNull();
    expect(extractSummary({ summary: 42 })).toBeNull();
  });
});
