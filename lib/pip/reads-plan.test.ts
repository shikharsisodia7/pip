import { describe, expect, it } from 'vitest';
import { tokenizeDisplay } from '@/lib/text';
import type { PatternFinding } from '@/lib/types';
import {
  buildPlan,
  chooseMistakeWords,
  emotionLineIndexes,
  fallbackMisreading,
  isValidMisreading,
  replaceCore,
  splitSentences,
  substituteWord,
} from './reads-plan';

const PAGE = 'Then a loud boom shook the trees. Tara jumped up. "Oh no! What was that?" she cried.';
const EMOTION = 'Oh no! What was that?';

const finding = (id: string): PatternFinding => ({
  id, kidLabel: id, teacherLabel: id, evidenceWords: [], confidence: 0.8,
});

describe('splitSentences', () => {
  it('covers every page word exactly once with matching indexes', () => {
    const tokens = tokenizeDisplay(PAGE);
    const sentences = splitSentences(PAGE);
    expect(sentences[0].wordStart).toBe(0);
    expect(sentences[sentences.length - 1].wordEnd).toBe(tokens.length);
    for (let i = 1; i < sentences.length; i++) expect(sentences[i].wordStart).toBe(sentences[i - 1].wordEnd);
    for (const s of sentences) {
      const own = tokenizeDisplay(s.text).map((t) => t.display);
      expect(own).toEqual(tokens.slice(s.wordStart, s.wordEnd).map((t) => t.display));
      expect(s.spokenText).toBe(s.text);
    }
  });

  it('keeps a quoted line with its dialogue tag', () => {
    const texts = splitSentences(PAGE).map((s) => s.text);
    expect(texts).toEqual(['Then a loud boom shook the trees.', 'Tara jumped up.', '"Oh no! What was that?" she cried.']);
  });

  it('handles text with no final punctuation and empty text', () => {
    expect(splitSentences('The owl hooted. It was late').map((s) => s.text)).toEqual(['The owl hooted.', 'It was late']);
    expect(splitSentences('')).toEqual([]);
  });

  it('ignores dashes when counting words', () => {
    const text = 'Pip looked up — the moon was out. It was bright.';
    const sentences = splitSentences(text);
    expect(sentences[sentences.length - 1].wordEnd).toBe(tokenizeDisplay(text).length);
  });
});

describe('emotionLineIndexes', () => {
  it('finds the emotion line words on the page', () => {
    const idx = emotionLineIndexes(tokenizeDisplay(PAGE), EMOTION);
    expect([...idx]).toEqual([10, 11, 12, 13, 14]);
  });
});

describe('fallback misreadings', () => {
  it.each([
    ['thought', 'ough', 'thoft'],
    ['jumped', 'ed', 'jump'],
    ['stopped', 'ed', 'stop'],
    ['smile', 'silent-e', 'smil'],
    ['night', 'igh', 'nit'],
    ['think', 'th', 'tink'],
    ['loud', 'ou', 'lood'],
  ])('%s (%s) -> %s', (word, pattern, misread) => {
    const r = fallbackMisreading(word, pattern);
    expect(r?.misread).toBe(misread);
    expect(r && isValidMisreading(word, r.misread)).toBe(true);
  });

  it('gives silent e a short vowel spelling for the voice', () => {
    expect(fallbackMisreading('smile', 'silent-e')?.speakAs).toBe('smill');
  });

  it('rejects misreadings that would fuzzy-match the correct word', () => {
    expect(isValidMisreading('jumped', 'jumped')).toBe(false);
    expect(isValidMisreading('thought', 'thoughts')).toBe(false);
    expect(isValidMisreading('jumped', 'two words')).toBe(false);
    expect(isValidMisreading('jumped', 'jump')).toBe(true);
  });
});

describe('chooseMistakeWords', () => {
  const sentences = splitSentences(PAGE);

  it('plants on the diagnosed pattern', () => {
    const [m] = chooseMistakeWords(PAGE, sentences, [finding('ed')], 1, EMOTION);
    expect(m.correct).toBe('jumped');
    expect(m.patternId).toBe('ed');
  });

  it('never picks the first or last word, or a word in the emotion line', () => {
    // "cried" (last word) is the only other -ed word; "What" (wh) is in the emotion line.
    const picks = chooseMistakeWords(PAGE, sentences, [finding('wh'), finding('ed')], 2, EMOTION);
    for (const p of picks) {
      expect(p.wordIndex).toBeGreaterThan(0);
      expect(p.wordIndex).toBeLessThan(tokenizeDisplay(PAGE).length - 1);
      expect([10, 11, 12, 13, 14]).not.toContain(p.wordIndex);
    }
    expect(picks.map((p) => p.correct)).not.toContain('cried');
    expect(picks.map((p) => p.correct)).not.toContain('what');
  });

  it('never puts two mistakes in one sentence', () => {
    const picks = chooseMistakeWords(PAGE, sentences, [finding('ed'), finding('ou')], 2, EMOTION);
    expect(picks).toHaveLength(2);
    expect(new Set(picks.map((p) => p.sentenceIndex)).size).toBe(2);
  });

  it('uses the hardest pattern present when there is no diagnosis', () => {
    const [m] = chooseMistakeWords(PAGE, sentences, [], 1, EMOTION);
    expect(m.patternId).toBe('ed');
  });

  it('ignores unknown pattern ids', () => {
    const [m] = chooseMistakeWords(PAGE, sentences, [finding('not-a-pattern')], 1, EMOTION);
    expect(m.patternId).toBe('ed');
  });

  it('is deterministic', () => {
    const a = chooseMistakeWords(PAGE, sentences, [finding('ou')], 2, EMOTION);
    const b = chooseMistakeWords(PAGE, sentences, [finding('ou')], 2, EMOTION);
    expect(a).toEqual(b);
  });
});

describe('buildPlan', () => {
  const req = { pageIndex: 1, pageText: PAGE, patterns: [finding('ed')], count: 1, emotionLineText: EMOTION };

  it('builds a one-mistake plan with spokenText carrying the misreading', () => {
    const plan = buildPlan(req);
    expect(plan.pageIndex).toBe(1);
    expect(plan.mistakes).toHaveLength(1);
    const m = plan.mistakes[0];
    expect(m).toMatchObject({ wordIndex: 8, sentenceIndex: 1, correct: 'jumped', misread: 'jump', speakAs: 'jump', patternId: 'ed' });
    expect(plan.sentences[1].spokenText).toBe('Tara jump up.');
    expect(plan.sentences[1].text).toBe('Tara jumped up.');
    expect(m.reaction.length).toBeGreaterThan(3);
    expect(m.reaction).not.toMatch(/[—–]/);
  });

  it('defaults to two mistakes', () => {
    const plan = buildPlan({ ...req, count: undefined, patterns: [finding('ed'), finding('ou')] });
    expect(plan.mistakes).toHaveLength(2);
    for (const m of plan.mistakes) {
      const s = plan.sentences[m.sentenceIndex];
      expect(tokenizeDisplay(s.spokenText)).toHaveLength(s.wordEnd - s.wordStart);
    }
  });

  it('uses valid model wording and falls back on invalid wording', () => {
    const good = buildPlan(req, [{ correct: 'jumped', misread: 'jumpt', speakAs: 'jumpt', reaction: '[happy] Jumped! Thanks — teacher!' }]);
    expect(good.mistakes[0].misread).toBe('jumpt');
    expect(good.mistakes[0].reaction).toBe('Jumped! Thanks, teacher!');
    expect(good.sentences[1].spokenText).toBe('Tara jumpt up.');

    const bad = buildPlan(req, [{ correct: 'jumped', misread: 'jumped', speakAs: 'two words', reaction: '' }]);
    expect(bad.mistakes[0].misread).toBe('jump');
    expect(bad.mistakes[0].reaction.length).toBeGreaterThan(3);
  });

  it('survives an empty page', () => {
    const plan = buildPlan({ pageIndex: 0, pageText: '', patterns: [] });
    expect(plan).toEqual({ pageIndex: 0, sentences: [], mistakes: [] });
  });
});

describe('word display helpers', () => {
  it('keeps punctuation and capitals', () => {
    expect(replaceCore('trees.', 'treez')).toBe('treez.');
    expect(replaceCore('"Oh', 'ah')).toBe('"Ah');
    expect(replaceCore('that?"', 'dat')).toBe('dat?"');
  });

  it('substitutes one word in a sentence', () => {
    const [s] = splitSentences('Then a loud boom shook the trees.');
    expect(substituteWord(s, 2, 'lood')).toBe('Then a lood boom shook the trees.');
  });
});
