import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATTERNS } from '@/lib/patterns';
import { claudeJson, loadFixture } from '@/lib/server/claudeJson';
import {
  createPracticeBook, fallbackPracticeBook, requestPattern, validatePracticeBook,
} from './practice-book';
import { POST } from './route';

vi.mock('@/lib/server/claudeJson', async (importOriginal) => ({
  ...await importOriginal<typeof import('@/lib/server/claudeJson')>(),
  claudeJson: vi.fn(),
}));

const generate = vi.mocked(claudeJson);
const finding = (id: string) => requestPattern({ pattern: { id } });

beforeEach(() => { generate.mockReset(); });

describe('practice book fallbacks', () => {
  it.each(PATTERNS.map((pattern) => pattern.id))('has six valid short sentences for %s', (id) => {
    const book = fallbackPracticeBook(finding(id));
    expect(validatePracticeBook(book, id)).toEqual(book);
    expect(book.sentences.join(' ')).toMatch(/Pip the owl/);
    expect(book.pattern.evidenceWords).toEqual([]);
    expect(book.pattern.confidence).toBe(0);
  });

  it.each(['ough', 'igh', 'ed', 'silent-e', 'ea', 'ou'])('loads the %s fixture in mock mode', async (id) => {
    generate.mockImplementation(loadFixture);
    const pattern = finding(id);
    expect(await createPracticeBook(pattern, true)).toEqual(fallbackPracticeBook(pattern));
    expect(generate).toHaveBeenCalledExactlyOnceWith(expect.objectContaining({
      mock: true, fixture: `fixtures/claude/practice-${id}.json`,
    }));
  });

  it('uses the generic story with the requested example for other taxonomy patterns', async () => {
    generate.mockImplementation(loadFixture);
    const book = await createPracticeBook(finding('er'), true);
    expect(book.sentences.every((sentence) => sentence.includes('bird'))).toBe(true);
    expect(validatePracticeBook(book, 'er')).toEqual(book);
  });

  it.each([undefined, null, [], {}, { pattern: null }, { pattern: { id: '../unknown' } }])(
    'uses the generic pattern for invalid input %j', (input) => {
      expect(finding('ee')).toEqual(requestPattern(input));
    },
  );
});

describe('practice book validation and retry', () => {
  const pattern = finding('igh');
  const valid = fallbackPracticeBook(pattern);

  it.each([5, 7])('rejects %i sentences', (count) => {
    const sentences = Array.from({ length: count }, () => valid.sentences[0]);
    expect(() => validatePracticeBook({ ...valid, sentences }, 'igh')).toThrow('exactly 6');
  });

  it.each([
    ['ed', 'Pip sat on a red bed.'],
    ['silent-e', 'Pip can have some love.'],
    ['ou', 'Pip thought you could help.'],
  ])('uses the shared %s matcher, including its exceptions', (id, sentence) => {
    const book = fallbackPracticeBook(finding(id));
    book.sentences[2] = sentence;
    expect(() => validatePracticeBook(book, id)).toThrow(`Sentence 3 needs a word matching pattern ${id}`);
  });

  it.each([
    'The bright light shone in the night as Pip flew high.',
    'Pip took flight. It was night.',
    'Pip took flight\u2014at night.',
    'Pip took flight',
  ])('rejects copy that is too long or is not a single sentence: %s', (sentence) => {
    expect(() => validatePracticeBook({ ...valid, sentences: [sentence, ...valid.sentences.slice(1)] }, 'igh'))
      .toThrow('Sentence 1 must be one short sentence');
  });

  it('retries once with the validation error and accepts a corrected book', async () => {
    generate.mockResolvedValueOnce({ ...valid, sentences: ['Pip sat.', ...valid.sentences.slice(1)] })
      .mockResolvedValueOnce(valid);
    expect(await createPracticeBook(pattern, true)).toEqual(valid);
    expect(generate).toHaveBeenCalledTimes(2);
    expect(generate.mock.calls[1][0].prompt).toContain('Sentence 1 needs a word matching pattern igh');
  });

  it('falls back after a second invalid book', async () => {
    generate.mockResolvedValue({ ...valid, sentences: [] });
    expect(await createPracticeBook(pattern, true)).toEqual(valid);
    expect(generate).toHaveBeenCalledTimes(2);
    expect(generate.mock.calls[1][0].prompt).toContain('Return exactly 6 sentences.');
  });

  it('falls back if the shared helper throws', async () => {
    generate.mockRejectedValue(new Error('Service unavailable'));
    expect(await createPracticeBook(pattern, true)).toEqual(valid);
    expect(generate).toHaveBeenCalledTimes(1);
  });

  it('retains supplied evidence instead of model-generated findings', async () => {
    const supplied = { ...pattern, evidenceWords: ['night'], confidence: 0.6 };
    generate.mockResolvedValue({ ...valid, pattern: { ...pattern, evidenceWords: ['flight'], confidence: 1 } });
    expect((await createPracticeBook(supplied, true)).pattern).toEqual(supplied);
    expect(generate.mock.calls[0][0].prompt).toContain('"evidenceWords":[],"confidence":0');
  });
});

describe('POST /api/practice-book', () => {
  it('passes the mock request header through and returns a complete book', async () => {
    generate.mockImplementation(loadFixture);
    const response = await POST(new Request('http://localhost/api/practice-book', {
      method: 'POST', headers: { 'x-pip-mock': '1' },
      body: JSON.stringify({ pattern: finding('ough') }),
    }));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(fallbackPracticeBook(finding('ough')));
    expect(generate.mock.calls[0][0].mock).toBe(true);
  });

  it('returns a valid generic book for malformed JSON even when generation fails', async () => {
    generate.mockRejectedValue(new Error('Fixture unavailable'));
    const response = await POST(new Request('http://localhost/api/practice-book', {
      method: 'POST', body: '{',
    }));
    expect(response.status).toBe(200);
    const book = await response.json();
    expect(validatePracticeBook(book, 'ee')).toEqual(book);
  });
});
