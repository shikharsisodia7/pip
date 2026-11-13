import { readFileSync } from 'node:fs';
import { alignWords } from '../lib/reading/align';
import { tokenize } from '../lib/text';
import type { Transcript } from '../lib/types';

interface Input {
  expectedText: string;
  transcript: Transcript;
  referenceWords?: string[];
}

function align(input: Input) {
  if (typeof input?.expectedText !== 'string' ||
      typeof input?.transcript?.text !== 'string' ||
      !Array.isArray(input?.transcript?.words)) {
    throw new Error('Expected expectedText and a transcript with text and timed words.');
  }
  for (const word of input.transcript.words) {
    if (typeof word.text !== 'string' || !Number.isFinite(word.start) ||
        !Number.isFinite(word.end) || word.start < 0 || word.end < word.start) {
      throw new Error('Each transcript word must have text and valid timestamps.');
    }
  }
  const expected = tokenize(input.expectedText);
  if (input.referenceWords !== undefined) {
    if (!Array.isArray(input.referenceWords) ||
        input.referenceWords.length !== expected.length ||
        input.referenceWords.some((word, i) => {
          if (typeof word !== 'string') return true;
          const tokens = tokenize(word);
          return tokens.length !== 1 || tokens[0] !== expected[i];
        })) {
      throw new Error('Human word labels do not map one-to-one to app word indexes.');
    }
  }
  const result = alignWords(input.expectedText, input.transcript);
  if (result.words.length !== expected.length ||
      result.words.some((word, i) => word.index !== i || word.expected !== expected[i])) {
    throw new Error('Alignment does not preserve the expected word indexes.');
  }
  return result;
}

try {
  const input = JSON.parse(readFileSync(0, 'utf8')) as Input | Input[];
  process.stdout.write(JSON.stringify(Array.isArray(input) ? input.map(align) : align(input)) + '\n');
} catch (error) {
  console.error(error instanceof Error ? error.message : 'Alignment failed.');
  process.exitCode = 1;
}
