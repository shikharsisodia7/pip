import { describe, expect, it } from 'vitest';
import { buildTranscript, friendlyListenError, liveText } from './transcript';

describe('buildTranscript', () => {
  it('keeps spoken words and fillers, drops spacing and audio events, and applies the offset', () => {
    const t = buildTranscript(
      [
        {
          text: 'Tara um thought',
          words: [
            { text: 'Tara', start: 0.1, end: 0.5, type: 'word' },
            { text: ' ', start: 0.5, end: 0.6, type: 'spacing' },
            { text: 'um', start: 0.6, end: 0.9, type: 'word' },
            { text: '(cough)', start: 0.9, end: 1.0, type: 'audio_event' },
            { text: 'thought', start: 1.0, end: 1.4, type: 'word' },
          ],
        },
      ],
      '',
      1.5,
    );
    expect(t.text).toBe('Tara um thought');
    expect(t.words).toEqual([
      { text: 'Tara', start: 1.6, end: 2 },
      { text: 'um', start: 2.1, end: 2.4 },
      { text: 'thought', start: 2.5, end: 2.9 },
    ]);
  });

  it('leaves absolute times from later segments alone', () => {
    const t = buildTranscript(
      [
        { text: 'a', words: [{ text: 'a', start: 0, end: 1, type: 'word' }] },
        { text: 'b', words: [{ text: 'b', start: 37, end: 37.4, type: 'word' }] },
      ],
      '',
      0,
    );
    expect(t.words.map((w) => w.start)).toEqual([0, 37]);
  });

  it('shifts a later segment that restarts at zero so times stay in order', () => {
    const t = buildTranscript(
      [
        { text: 'a', words: [{ text: 'a', start: 0, end: 36, type: 'word' }] },
        { text: 'b', words: [{ text: 'b', start: 0.2, end: 0.6, type: 'word' }] },
      ],
      '',
      0,
    );
    expect(t.words[1].start).toBeGreaterThan(t.words[0].end);
    expect(t.words[1].end - t.words[1].start).toBeCloseTo(0.4);
  });

  it('gives a fallback tail evenly spaced times after the committed words', () => {
    const t = buildTranscript(
      [{ text: 'Tara', words: [{ text: 'Tara', start: 0, end: 0.5, type: 'word' }] }],
      'thought the night',
      0,
    );
    expect(t.text).toBe('Tara thought the night');
    expect(t.words.map((w) => w.text)).toEqual(['Tara', 'thought', 'the', 'night']);
    for (let i = 1; i < t.words.length; i++) expect(t.words[i].start).toBeGreaterThan(t.words[i - 1].start);
    expect(t.words[1].start).toBeGreaterThan(0.5);
  });

  it('builds a timed transcript from a partial alone', () => {
    const t = buildTranscript([], 'she look out', 0.4);
    expect(t.words).toHaveLength(3);
    expect(t.words[0].start).toBeCloseTo(0.4);
  });

  it('returns an empty transcript when nothing was heard', () => {
    expect(buildTranscript([], '', 0)).toEqual({ text: '', words: [] });
  });
});

describe('liveText', () => {
  it('joins committed text and the current partial', () => {
    expect(liveText(['Tara thought the night was too quiet.'], 'She look')).toBe(
      'Tara thought the night was too quiet. She look',
    );
    expect(liveText([], '')).toBe('');
  });
});

describe('friendlyListenError', () => {
  it('explains a blocked microphone', () => {
    const err = Object.assign(new Error('Permission denied'), { name: 'NotAllowedError' });
    expect(friendlyListenError(err)).toMatch(/allow the microphone/);
    expect(friendlyListenError('Permission denied')).toMatch(/allow the microphone/);
  });
  it('explains a missing microphone', () => {
    expect(friendlyListenError(Object.assign(new Error('Requested device not found'), { name: 'NotFoundError' }))).toMatch(
      /No microphone/,
    );
  });
  it('never uses an em dash', () => {
    for (const e of ['Permission denied', 'Requested device not found', 'Could not start audio source', 'x', 'insecure']) {
      expect(friendlyListenError(e)).not.toContain('—');
    }
  });
});
