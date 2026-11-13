// Deterministic planning for "Pip reads it wrong".
//
// Everything here is plain TypeScript with no network: sentence splitting with
// page word indexes, choosing which words Pip misreads, the per-pattern fallback
// misreadings, and validation of any model-written misreading. The route only
// asks Claude to improve the wording of misread/speakAs/reaction; it never lets
// the model choose words or indexes.

import { fuzzyEqual, normalizeToken, tokenizeDisplay, type Token } from '@/lib/text';
import { getPattern, PATTERNS } from '@/lib/patterns';
import type { PatternFinding, PipPlan, PipSentence, PlantedMistake } from '@/lib/types';

export interface PlanRequest {
  pageIndex: number;
  pageText: string;
  patterns: PatternFinding[];
  /** Optional. 1 plants a single mistake (2 minute path). Default 2. */
  count?: number;
  /** Optional. Words inside this line are never misread. */
  emotionLineText?: string;
}

/** What Claude may supply for one chosen word. Everything else is ours. */
export interface MistakeWording {
  correct: string;
  misread: string;
  speakAs: string;
  reaction: string;
}

/* -------------------------------------------------------------------------- */
/* Sentences                                                                  */
/* -------------------------------------------------------------------------- */

const SENTENCE_END = /[.!?]+["'”’)\]]*$/;

/** Net change in "inside a quotation" for one token. */
function quoteToggles(display: string): number {
  let n = 0;
  for (const ch of display) if (ch === '"') n++;
  return n;
}

/**
 * Splits page text into sentences. wordStart/wordEnd are page word indexes
 * (tokenizeDisplay(pageText)), end exclusive. Sentence text is the page tokens
 * joined with single spaces, so tokenizeDisplay(sentence.text) lines up 1:1 with
 * the page range, which is what keeps TTS word highlighting on the right words.
 * A quoted line and its dialogue tag ("Oh no!" she cried.) stay one sentence.
 */
export function splitSentences(pageText: string): PipSentence[] {
  const tokens = tokenizeDisplay(pageText);
  const sentences: PipSentence[] = [];
  let start = 0;
  let inStraightQuote = false;
  let curlyDepth = 0;

  const close = (end: number) => {
    if (end <= start) return;
    const text = tokens.slice(start, end).map((t) => t.display).join(' ');
    sentences.push({ index: sentences.length, text, spokenText: text, wordStart: start, wordEnd: end });
    start = end;
  };

  for (let i = 0; i < tokens.length; i++) {
    const d = tokens[i].display;
    if (quoteToggles(d) % 2 === 1) inStraightQuote = !inStraightQuote;
    curlyDepth += (d.match(/“/g)?.length ?? 0) - (d.match(/”/g)?.length ?? 0);
    if (curlyDepth < 0) curlyDepth = 0;

    if (!SENTENCE_END.test(d)) continue;
    if (inStraightQuote || curlyDepth > 0) continue;
    const next = tokens[i + 1]?.display ?? '';
    // A closing quote followed by a lowercase word is a dialogue tag: keep going.
    if (/["”’']$/.test(d) && /^[a-z]/.test(next)) continue;
    close(i + 1);
  }
  close(tokens.length);
  return sentences;
}

/** Page word indexes covered by the emotion line, if it appears on the page. */
export function emotionLineIndexes(pageTokens: Token[], emotionLineText?: string): Set<number> {
  const out = new Set<number>();
  if (!emotionLineText) return out;
  const line = tokenizeDisplay(emotionLineText).map((t) => t.norm);
  if (!line.length) return out;
  for (let i = 0; i + line.length <= pageTokens.length; i++) {
    if (line.every((w, k) => pageTokens[i + k].norm === w)) {
      for (let k = 0; k < line.length; k++) out.add(i + k);
    }
  }
  return out;
}

/* -------------------------------------------------------------------------- */
/* Fallback misreadings                                                       */
/* -------------------------------------------------------------------------- */

const VOWELS = /[aeiou]/;

/** Makes a short-vowel spelling the TTS voice will read with a short vowel. */
function shortVowelSpelling(word: string): string {
  const last = word.slice(-1);
  const prev = word.slice(-2, -1);
  if (!last || VOWELS.test(last) || !VOWELS.test(prev)) return word;
  if (last === 'k') return `${word.slice(0, -1)}ck`;
  if (last === 'v' || last === 'x' || last === 'w' || last === 'y') return word;
  return word + last;
}

function dropEd(word: string): string {
  if (word.endsWith('ied') && word.length > 4) return `${word.slice(0, -3)}y`;
  const stem = word.slice(0, -2);
  // stopped -> stop, hugged -> hug (but not "called" -> "cal")
  if (/([bdgmnprt])\1$/.test(stem)) return stem.slice(0, -1);
  return stem;
}

interface Misreading { misread: string; speakAs: string }

const same = (misread: string): Misreading => ({ misread, speakAs: misread });

/**
 * The child-realistic misreading for each pattern, used whenever Claude is
 * unavailable or returns something invalid. Input is a normalized word.
 */
export const FALLBACK_MISREADINGS: Record<string, (w: string) => Misreading> = {
  // ough said as "off": thought -> thoft, rough -> roff
  ough: (w) => same(w.includes('ought') ? w.replace('ought', 'oft') : w.replace('ough', 'off')),
  // igh read with a short i: night -> nit
  igh: (w) => {
    const m = w.replace('igh', 'i');
    return { misread: m, speakAs: shortVowelSpelling(m) };
  },
  // drop the -ed ending: jumped -> jump
  ed: (w) => same(dropEd(w)),
  // ignore the silent e, short vowel: smile -> smil
  'silent-e': (w) => {
    const m = w.slice(0, -1);
    return { misread: m, speakAs: shortVowelSpelling(m) };
  },
  // ou read as "oo": loud -> lood
  ou: (w) => same(w.replace('ou', 'oo')),
  // ea read as long a: dream -> draym
  ea: (w) => same(w.replace('ea', 'ay')),
  // r-controlled vowel read as "ar": bird -> bard
  er: (w) => same(w.replace(/er|ir|ur/, 'ar')),
  // ow read as "oo": down -> doon
  ow: (w) => same(w.replace('ow', 'oo')),
  // vowel team read with a short vowel: rain -> ran, play -> plah
  ai: (w) => {
    if (w.includes('ai')) {
      const m = w.replace('ai', 'a');
      return { misread: m, speakAs: shortVowelSpelling(m) };
    }
    return same(w.replace('ay', 'ah'));
  },
  oa: (w) => {
    const m = w.replace('oa', 'o');
    return { misread: m, speakAs: shortVowelSpelling(m) };
  },
  oo: (w) => {
    const m = w.replace('oo', 'o');
    return { misread: m, speakAs: shortVowelSpelling(m) };
  },
  oi: (w) => same(w.replace(/oi|oy/, 'o')),
  ar: (w) => same(w.replace('ar', 'ur')),
  or: (w) => same(w.replace('or', 'ur')),
  // wh read as h: what -> hat
  wh: (w) => same(w.replace(/^wh/, 'h')),
  ee: (w) => {
    const m = w.replace('ee', 'e');
    return { misread: m, speakAs: shortVowelSpelling(m) };
  },
  // digraphs read as one letter: think -> tink, shook -> sook, chin -> kin
  th: (w) => same(w.replace('th', 't')),
  sh: (w) => same(w.replace('sh', 's')),
  ch: (w) => same(w.replace('ch', 'k')),
};

/** Last resort for an unknown pattern id: change the first vowel group to "a". */
function genericMisreading(w: string): Misreading {
  return same(w.replace(/[aeiou]+/, (v) => (v === 'a' ? 'o' : 'a')));
}

const SINGLE_WORD = /^[a-z][a-z'-]{0,23}$/i;

/** A misreading is usable when it is one word that does not match the correct word. */
export function isValidMisreading(correct: string, misread: string): boolean {
  const m = misread.trim();
  if (!SINGLE_WORD.test(m)) return false;
  const nm = normalizeToken(m);
  const nc = normalizeToken(correct);
  if (!nm || nm === nc) return false;
  // If these fuzzy-matched, a child repeating Pip's misreading would count as a catch.
  return !fuzzyEqual(nm, nc);
}

export function isValidSpeakAs(speakAs: string): boolean {
  return SINGLE_WORD.test(speakAs.trim()) && normalizeToken(speakAs).length > 0;
}

export function fallbackMisreading(word: string, patternId: string): Misreading | null {
  const w = normalizeToken(word);
  const fn = FALLBACK_MISREADINGS[patternId] ?? genericMisreading;
  const r = fn(w);
  if (isValidMisreading(w, r.misread) && isValidSpeakAs(r.speakAs)) return r;
  const g = genericMisreading(w);
  if (isValidMisreading(w, g.misread) && isValidSpeakAs(g.speakAs)) return g;
  return null;
}

const cap = (s: string) => (s ? s[0].toUpperCase() + s.slice(1) : s);

export function fallbackReaction(correct: string, n: number): string {
  const c = cap(correct);
  const lines = [
    `Oh! ${c}! Thank you, teacher!`,
    `${c}! Of course! You are really good at this.`,
  ];
  return lines[n % lines.length];
}

/** Keeps a model-written reaction short, plain and free of tags and em dashes. */
export function cleanReaction(reaction: string): string | null {
  const r = reaction
    .replace(/\[[^\]]*\]/g, ' ')
    .replace(/\s*[—–]\s*/g, ', ')
    .replace(/\s+/g, ' ')
    .trim();
  if (r.length < 3 || r.length > 120) return null;
  return r;
}

/* -------------------------------------------------------------------------- */
/* Word display helpers                                                       */
/* -------------------------------------------------------------------------- */

/**
 * Replaces the letters of a printed token with another word, keeping the
 * surrounding punctuation and the leading capital: ("that?\"", "dat") -> "dat?\"".
 */
export function replaceCore(display: string, word: string): string {
  const m = display.match(/^([^A-Za-z0-9]*)(.*?)([^A-Za-z0-9']*)$/);
  if (!m) return word;
  const [, pre, core, post] = m;
  const out = /^[A-Z]/.test(core) ? cap(word) : word;
  return `${pre}${out}${post}`;
}

/** Sentence text with one page word swapped, same token count as the original. */
export function substituteWord(sentence: PipSentence, wordIndex: number, replacement: string): string {
  const tokens = tokenizeDisplay(sentence.text);
  const k = wordIndex - sentence.wordStart;
  if (k < 0 || k >= tokens.length) return sentence.text;
  return tokens.map((t, i) => (i === k ? replaceCore(t.display, replacement) : t.display)).join(' ');
}

/* -------------------------------------------------------------------------- */
/* Choosing mistakes                                                          */
/* -------------------------------------------------------------------------- */

export interface ChosenWord {
  wordIndex: number;
  sentenceIndex: number;
  correct: string;   // normalized
  display: string;   // as printed
  patternId: string;
}

/**
 * Picks which words Pip misreads. Deterministic. Rules:
 * - `count` mistakes (1 or 2), never two in one sentence
 * - never the first or last word of the page, never inside the emotion line
 * - diagnosed patterns first (top 2, in the order given); with no usable
 *   diagnosis, the hardest taxonomy pattern present on the page
 */
export function chooseMistakeWords(
  pageText: string,
  sentences: PipSentence[],
  patterns: PatternFinding[],
  count: number,
  emotionLineText?: string,
): ChosenWord[] {
  const tokens = tokenizeDisplay(pageText);
  const n = tokens.length;
  if (n < 3) return [];
  const blocked = emotionLineIndexes(tokens, emotionLineText);
  const sentenceOf = (i: number) => sentences.findIndex((s) => i >= s.wordStart && i < s.wordEnd);

  const eligible = (i: number) =>
    i > 0 && i < n - 1 && !blocked.has(i) && tokens[i].norm.length >= 2;

  const diagnosed: string[] = [];
  for (const p of patterns ?? []) {
    if (!p || !getPattern(p.id) || diagnosed.includes(p.id)) continue;
    const present = tokens.some((t, i) => eligible(i) && getPattern(p.id)!.test(t.norm));
    if (present) diagnosed.push(p.id);
    if (diagnosed.length === 2) break;
  }
  const rest = PATTERNS.map((p) => p.id).filter((id) => !diagnosed.includes(id));

  const chosen: ChosenWord[] = [];
  const usedSentences = new Set<number>();
  const usedPatterns = new Set<string>();
  const want = Math.max(1, Math.min(2, Math.floor(count) || 2));

  for (let k = 0; k < want; k++) {
    const order = [
      ...diagnosed.filter((id) => !usedPatterns.has(id)),
      ...diagnosed.filter((id) => usedPatterns.has(id)),
      ...rest,
    ];
    let pick: ChosenWord | null = null;
    for (const id of order) {
      const pattern = getPattern(id)!;
      for (let i = 0; i < n && !pick; i++) {
        if (!eligible(i) || !pattern.test(tokens[i].norm)) continue;
        if (chosen.some((c) => c.wordIndex === i)) continue;
        const si = sentenceOf(i);
        if (si < 0 || usedSentences.has(si)) continue;
        if (!fallbackMisreading(tokens[i].norm, id)) continue;
        pick = { wordIndex: i, sentenceIndex: si, correct: tokens[i].norm, display: tokens[i].display, patternId: id };
      }
      if (pick) break;
    }
    if (!pick) break;
    chosen.push(pick);
    usedSentences.add(pick.sentenceIndex);
    usedPatterns.add(pick.patternId);
  }
  return chosen.sort((a, b) => a.wordIndex - b.wordIndex);
}

/* -------------------------------------------------------------------------- */
/* Whole plan                                                                 */
/* -------------------------------------------------------------------------- */

/**
 * Builds the plan. `wordings` (from Claude, possibly empty) are matched to the
 * chosen words by the correct word and validated field by field; anything
 * missing or invalid falls back to the deterministic table.
 */
export function buildPlan(req: PlanRequest, wordings: MistakeWording[] = []): PipPlan {
  const pageText = typeof req.pageText === 'string' ? req.pageText : '';
  const sentences = splitSentences(pageText);
  const chosen = chooseMistakeWords(pageText, sentences, req.patterns ?? [], req.count ?? 2, req.emotionLineText);

  const mistakes: PlantedMistake[] = chosen.map((c, n) => {
    const fb = fallbackMisreading(c.correct, c.patternId)!;
    const w = wordings.find((x) => x && normalizeToken(String(x.correct ?? '')) === c.correct);

    let misread = fb.misread;
    let speakAs = fb.speakAs;
    if (w && typeof w.misread === 'string' && isValidMisreading(c.correct, w.misread)) {
      misread = normalizeToken(w.misread);
      speakAs = typeof w.speakAs === 'string' && isValidSpeakAs(w.speakAs) ? w.speakAs.trim() : misread;
      // The spoken form must not sound like the correct word either.
      if (!isValidMisreading(c.correct, speakAs)) speakAs = misread;
    }
    const reaction = (w && typeof w.reaction === 'string' && cleanReaction(w.reaction)) || fallbackReaction(c.correct, n);

    return {
      wordIndex: c.wordIndex,
      sentenceIndex: c.sentenceIndex,
      correct: c.correct,
      misread,
      speakAs,
      patternId: c.patternId,
      reaction,
    };
  });

  for (const m of mistakes) {
    const s = sentences[m.sentenceIndex];
    s.spokenText = substituteWord(s, m.wordIndex, m.speakAs);
  }

  return { pageIndex: Number.isFinite(req.pageIndex) ? req.pageIndex : 0, sentences, mistakes };
}

/** How a misread word is shown on screen: the misreading with the printed punctuation. */
export function misreadDisplay(display: string, misread: string): string {
  return replaceCore(display, misread);
}
