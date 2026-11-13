import { z } from 'zod';
import { getPattern } from '@/lib/patterns';
import { claudeJson } from '@/lib/server/claudeJson';
import { tokenize } from '@/lib/text';
import type { PatternFinding, PracticeBook } from '@/lib/types';
import ough from '@/fixtures/claude/practice-ough.json';
import igh from '@/fixtures/claude/practice-igh.json';
import ed from '@/fixtures/claude/practice-ed.json';
import silentE from '@/fixtures/claude/practice-silent-e.json';
import ea from '@/fixtures/claude/practice-ea.json';
import ou from '@/fixtures/claude/practice-ou.json';
import generic from '@/fixtures/claude/practice-generic.json';

const fixtures: Record<string, PracticeBook> = { ough, igh, ed, 'silent-e': silentE, ea, ou };

const patternSchema = z.object({
  id: z.string(),
  kidLabel: z.string(),
  teacherLabel: z.string(),
  evidenceWords: z.array(z.string()),
  confidence: z.number().min(0).max(1),
});

const bookSchema = z.object({
  title: z.string().trim().min(1).max(64),
  pattern: patternSchema,
  sentences: z.array(z.string().trim().min(1)),
});

const requestSchema = z.object({
  pattern: z.object({
    id: z.string(),
    evidenceWords: z.array(z.string()).catch([]),
    confidence: z.number().min(0).max(1).catch(0),
  }),
});

/** Use taxonomy labels and keep only evidence actually supplied by the caller. */
export function requestPattern(body: unknown): PatternFinding {
  const parsed = requestSchema.safeParse(body);
  const supplied = parsed.success ? parsed.data.pattern : undefined;
  const pattern = supplied ? getPattern(supplied.id) : undefined;
  if (!pattern || !supplied) return { ...generic.pattern, evidenceWords: [] };
  return {
    id: pattern.id,
    kidLabel: pattern.kidLabel,
    teacherLabel: pattern.teacherLabel,
    evidenceWords: supplied.evidenceWords,
    confidence: supplied.confidence,
  };
}

/** Bundled fixtures keep the fallback available even if disk or network calls fail. */
export function fallbackPracticeBook(pattern: PatternFinding): PracticeBook {
  const target = getPattern(pattern.id);
  if (!target) return { ...generic, pattern: { ...generic.pattern, evidenceWords: [] } };
  const fixture = fixtures[pattern.id];
  return {
    title: fixture?.title ?? generic.title,
    pattern,
    sentences: fixture
      ? [...fixture.sentences]
      : generic.sentences.map((sentence) => sentence.replace(/\btree\b/g, target.example)),
  };
}

export function validatePracticeBook(value: unknown, patternId: string): PracticeBook {
  const book = bookSchema.parse(value);
  const target = getPattern(patternId);
  if (!target) throw new Error('Use a supported phonics pattern.');
  if (book.pattern.id !== patternId) throw new Error(`Use pattern ${patternId}.`);
  if (book.sentences.length !== 6) throw new Error('Return exactly 6 sentences.');
  if (/\u2014/.test(book.title)) throw new Error('Do not use em dashes in the title.');

  book.sentences.forEach((sentence, index) => {
    const words = tokenize(sentence);
    if (!/^[^.!?\u2014]+[.!?]$/.test(sentence) || words.length > 10 || sentence.length > 65) {
      throw new Error(`Sentence ${index + 1} must be one short sentence, at most 10 words and 65 characters, with no em dashes.`);
    }
    if (!words.some((word) => target.test(word))) {
      throw new Error(`Sentence ${index + 1} needs a word matching pattern ${patternId}, such as ${target.example}.`);
    }
  });
  return book;
}

export async function createPracticeBook(pattern: PatternFinding, mock: boolean): Promise<PracticeBook> {
  const target = getPattern(pattern.id);
  if (!target) return fallbackPracticeBook(pattern);

  const prompt = [
    `Write a practice book for ${target.teacherLabel}. Example target word: ${target.example}.`,
    'Give it a short title and exactly 6 short, decodable sentences.',
    'Use kindergarten to grade 2 vocabulary and a tiny story arc starring an owl named Pip.',
    'Make the sentences dense with the target pattern. Every sentence must include at least one matching word.',
    'Use at most 10 words and 65 characters per sentence. End each sentence with punctuation.',
    'Use a warm tone. No grades, scores, em dashes, or extra sentences.',
    `Return { "title": string, "pattern": ${JSON.stringify({ ...pattern, evidenceWords: [], confidence: 0 })}, "sentences": string[] }.`,
  ].join('\n');
  let correction = '';

  for (let attempt = 0; attempt < 2; attempt++) {
    let result: PracticeBook;
    try {
      result = await claudeJson<PracticeBook>({
        name: 'practice-book',
        system: 'You write gentle, original phonics practice stories for early readers.',
        prompt: prompt + correction,
        schema: bookSchema,
        mock,
        fixture: `fixtures/claude/practice-${pattern.id}.json`,
        maxTokens: 900,
      });
    } catch {
      // The shared helper already retries invalid JSON and schema mismatches.
      return fallbackPracticeBook(pattern);
    }

    try {
      const book = validatePracticeBook(result, pattern.id);
      // The model writes the story, not the child's evidence or confidence.
      return { ...book, pattern };
    } catch (error) {
      const detail = error instanceof Error ? error.message : 'Invalid practice book.';
      correction = `\nThe previous attempt failed validation: ${detail.slice(0, 400)}\nReturn the corrected book.`;
    }
  }

  return fallbackPracticeBook(pattern);
}
