// FROZEN shared helper. Do not edit; ask the bootstrap owner for changes.
// Phonics taxonomy. PatternFinding.id must always be one of these ids.

import { normalizeToken, tokenizeDisplay } from './text';

export interface Pattern {
  id: string;
  kidLabel: string;
  teacherLabel: string;
  /** 1 (easy) to 5 (hard), used to pick "the hardest pattern on the page". */
  difficulty: number;
  /** Word that shows the pattern, for practice copy. */
  example: string;
  test(word: string): boolean;
}

const ED_EXCEPTIONS = new Set([
  'need', 'feed', 'seed', 'weed', 'deed', 'heed', 'reed', 'speed', 'bleed', 'breed', 'greed', 'steed',
  'bed', 'red', 'fed', 'led', 'wed', 'shed', 'sled', 'bred', 'sped', 'fled', 'shred',
  'hundred', 'sacred', 'naked', 'wicked', 'indeed', 'proceed', 'exceed', 'succeed',
]);

const SILENT_E_EXCEPTIONS = new Set([
  'have', 'give', 'live', 'love', 'come', 'some', 'done', 'gone', 'none', 'one', 'once',
  'were', 'there', 'where', 'here', 'move', 'lose', 'whose', 'above', 'glove', 'dove', 'were',
]);

const OU_EXCEPTIONS = new Set(['you', 'your', "you're", 'yours', 'could', 'would', 'should', 'four', 'pour', 'touch', 'young', 'soul']);

const has = (re: RegExp) => (word: string) => re.test(normalizeToken(word));

/** Ordered hardest first. */
export const PATTERNS: Pattern[] = [
  { id: 'ough', kidLabel: "the 'ough' sound", teacherLabel: 'vowel team: ough', difficulty: 5, example: 'thought', test: has(/ough/) },
  { id: 'igh', kidLabel: "the 'igh' sound", teacherLabel: 'vowel team: igh (-ight)', difficulty: 4, example: 'night', test: has(/igh/) },
  {
    id: 'ed', kidLabel: "words ending in '-ed'", teacherLabel: 'inflectional ending: -ed', difficulty: 3, example: 'jumped',
    test: (w) => { const n = normalizeToken(w); return n.length >= 4 && n.endsWith('ed') && !ED_EXCEPTIONS.has(n); },
  },
  {
    id: 'silent-e', kidLabel: 'the sneaky silent e', teacherLabel: 'VCe (silent e)', difficulty: 3, example: 'smile',
    test: (w) => { const n = normalizeToken(w); return !SILENT_E_EXCEPTIONS.has(n) && /(^|[^aeiou])[aeiou][bcdfgklmnprstvz]e$/.test(n); },
  },
  {
    id: 'ou', kidLabel: "the 'ou' sound", teacherLabel: 'vowel team: ou', difficulty: 3, example: 'loud',
    test: (w) => { const n = normalizeToken(w); return /ou/.test(n) && !/ough/.test(n) && !OU_EXCEPTIONS.has(n); },
  },
  { id: 'ea', kidLabel: "the 'ea' sound", teacherLabel: 'vowel team: ea', difficulty: 3, example: 'dream', test: has(/ea/) },
  { id: 'er', kidLabel: "the 'er' sound", teacherLabel: 'r-controlled vowel: er / ir / ur', difficulty: 3, example: 'bird', test: has(/er|ir|ur/) },
  { id: 'ow', kidLabel: "the 'ow' sound", teacherLabel: 'vowel team: ow', difficulty: 3, example: 'owl', test: has(/ow/) },
  { id: 'ai', kidLabel: "the 'ai' sound", teacherLabel: 'vowel team: ai / ay', difficulty: 2, example: 'rain', test: has(/ai|ay/) },
  { id: 'oa', kidLabel: "the 'oa' sound", teacherLabel: 'vowel team: oa', difficulty: 2, example: 'boat', test: has(/oa/) },
  { id: 'oo', kidLabel: "the 'oo' sound", teacherLabel: 'vowel team: oo', difficulty: 2, example: 'moon', test: has(/oo/) },
  { id: 'oi', kidLabel: "the 'oi' sound", teacherLabel: 'diphthong: oi / oy', difficulty: 2, example: 'boy', test: has(/oi|oy/) },
  { id: 'ar', kidLabel: "the 'ar' sound", teacherLabel: 'r-controlled vowel: ar', difficulty: 2, example: 'star', test: has(/ar/) },
  { id: 'or', kidLabel: "the 'or' sound", teacherLabel: 'r-controlled vowel: or', difficulty: 2, example: 'storm', test: has(/or/) },
  { id: 'wh', kidLabel: "the 'wh' sound", teacherLabel: 'digraph: wh', difficulty: 2, example: 'whisper', test: has(/^wh/) },
  { id: 'ee', kidLabel: "the 'ee' sound", teacherLabel: 'vowel team: ee', difficulty: 1, example: 'tree', test: has(/ee/) },
  { id: 'th', kidLabel: "the 'th' sound", teacherLabel: 'digraph: th', difficulty: 1, example: 'think', test: has(/th/) },
  { id: 'sh', kidLabel: "the 'sh' sound", teacherLabel: 'digraph: sh', difficulty: 1, example: 'ship', test: has(/sh/) },
  { id: 'ch', kidLabel: "the 'ch' sound", teacherLabel: 'digraph: ch', difficulty: 1, example: 'chin', test: has(/ch/) },
];

const BY_ID = new Map(PATTERNS.map((p) => [p.id, p]));

export function getPattern(id: string): Pattern | undefined {
  return BY_ID.get(id);
}

export function isPatternId(id: string): boolean {
  return BY_ID.has(id);
}

/** Every pattern the word contains, hardest first. */
export function patternsForWord(word: string): Pattern[] {
  return PATTERNS.filter((p) => p.test(word));
}

export interface PatternWord {
  /** Page word index (same indexes as tokenizeDisplay). */
  index: number;
  /** Normalized word. */
  word: string;
  /** Word as printed. */
  display: string;
}

/** Page words containing the pattern, with their page word indexes. */
export function wordsWithPattern(text: string, id: string): PatternWord[] {
  const p = BY_ID.get(id);
  if (!p) return [];
  return tokenizeDisplay(text)
    .map((t, index) => ({ index, word: t.norm, display: t.display }))
    .filter((w) => p.test(w.word));
}

/** The hardest taxonomy pattern that appears in the text, if any. */
export function hardestPatternIn(text: string): Pattern | undefined {
  const words = tokenizeDisplay(text).map((t) => t.norm);
  return PATTERNS.find((p) => words.some((w) => p.test(w)));
}
