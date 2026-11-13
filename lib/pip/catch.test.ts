import { describe, expect, it } from 'vitest';
import type { PlantedMistake, Transcript } from '@/lib/types';
import { detectCatch, isBareObjection } from './catch';

const mistake: PlantedMistake = {
  wordIndex: 8, sentenceIndex: 1, correct: 'thought', misread: 'thoft', speakAs: 'thoft',
  patternId: 'ough', reaction: 'Oh! Thought! Thank you, teacher!',
};

const said = (text: string): Transcript => ({
  text,
  words: text.split(/\s+/).filter(Boolean).map((w, i) => ({ text: w, start: i * 0.4, end: i * 0.4 + 0.3 })),
});

describe('detectCatch', () => {
  it('catches the bare correct word', () => {
    expect(detectCatch(said('thought'), mistake)).toBe(true);
  });

  it('catches the word inside a sentence with punctuation', () => {
    expect(detectCatch(said('No, it says thought.'), mistake)).toBe(true);
    expect(detectCatch(said('no it says Thought'), mistake)).toBe(true);
  });

  it('forgives one letter of recognition noise on long words', () => {
    expect(detectCatch(said('it says thougt'), mistake)).toBe(true);
  });

  it('works from text alone when there are no timed words', () => {
    expect(detectCatch({ text: 'no, thought', words: [] }, mistake)).toBe(true);
  });

  it('is false for empty, yes, or the misreading said back', () => {
    expect(detectCatch(said(''), mistake)).toBe(false);
    expect(detectCatch({ text: '', words: [] }, mistake)).toBe(false);
    expect(detectCatch(said('yes'), mistake)).toBe(false);
    expect(detectCatch(said('yeah you got it'), mistake)).toBe(false);
    expect(detectCatch(said('thoft'), mistake)).toBe(false);
    expect(detectCatch(null, mistake)).toBe(false);
  });

  it('keeps short words strict', () => {
    const short: PlantedMistake = { ...mistake, correct: 'jumped', misread: 'jump', speakAs: 'jump' };
    expect(detectCatch(said('jump'), short)).toBe(false);
    expect(detectCatch(said('no, jumped'), short)).toBe(true);
  });
});

describe('isBareObjection', () => {
  it('is true for no, wrong and that is not right without the word', () => {
    expect(isBareObjection(said('no'))).toBe(true);
    expect(isBareObjection(said("That's wrong!"))).toBe(true);
    expect(isBareObjection(said('wrong'))).toBe(true);
    expect(isBareObjection(said('nope'))).toBe(true);
    expect(isBareObjection(said("that's not right"))).toBe(true);
  });

  it('is false for yes, empty and real catches', () => {
    expect(isBareObjection(said('yes'))).toBe(false);
    expect(isBareObjection(said(''))).toBe(false);
    expect(isBareObjection(said('no it says thought'), mistake)).toBe(false);
  });

  it('does not mistake "know" for "no"', () => {
    expect(isBareObjection(said('I know'))).toBe(false);
  });
});
