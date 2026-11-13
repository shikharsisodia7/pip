import { describe, expect, it } from 'vitest';
import { tokenize } from '@/lib/text';
import { advanceCursor, INITIAL_CURSOR, matchForward, type CursorState } from './karaoke';

const PAGE = 'Tara thought the night was too quiet. She looked out at the bright moon and smiled.';
const expected = tokenize(PAGE);

function feed(partials: string[], start: CursorState = INITIAL_CURSOR): CursorState {
  return partials.reduce((s, p) => advanceCursor(s, expected, p), start);
}

describe('matchForward', () => {
  it('reads every word of a clean reading', () => {
    expect(matchForward(expected, tokenize(PAGE))).toBe(expected.length);
  });

  it('steps past a misread word once the next word is heard', () => {
    const spoken = tokenize('Tara thought the night was too quiet. She look out');
    expect(matchForward(expected, spoken)).toBe(10);
  });

  it('forgives up to two skipped page words', () => {
    expect(matchForward(expected, tokenize('Tara thought night'))).toBe(4);
    expect(matchForward(expected, tokenize('Tara was'))).toBe(1);
  });

  it('ignores filler words it cannot place', () => {
    expect(matchForward(expected, tokenize('um uh'))).toBe(0);
    expect(matchForward(expected, tokenize('Tara um thought'))).toBe(2);
  });

  it('starts from the given page word', () => {
    expect(matchForward(expected, tokenize('She looked'), 7)).toBe(9);
  });
});

describe('advanceCursor', () => {
  it('follows a growing partial transcript', () => {
    const s = feed(['Tara', 'Tara thought', 'Tara thought the night']);
    expect(s.cursor).toBe(4);
  });

  it('never moves backward when a partial is revised', () => {
    const s = feed(['Tara thought the night', 'Tara thought the']);
    expect(s.cursor).toBe(4);
  });

  it('continues from the cursor when the listener starts a new segment', () => {
    const s = feed(['Tara thought the night was too quiet.', 'She', 'She looked out']);
    expect(s.cursor).toBe(10);
  });

  it('treats an empty partial as the end of a segment', () => {
    const s = feed(['Tara thought', '', 'the night']);
    expect(s.cursor).toBe(4);
  });

  it('reaches the end on the demo reading', () => {
    const words = 'Tara thought the night was too quiet. She look out at the bright moon and smiled.'.split(' ');
    const partials = words.map((_, i) => words.slice(0, i + 1).join(' '));
    expect(feed(partials).cursor).toBe(expected.length);
  });
});
