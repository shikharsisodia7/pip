// FROZEN shared helper. Do not edit; ask the bootstrap owner for changes.
// Every module that compares spoken words with page words goes through these
// functions, so page display, karaoke, alignment and catch detection agree on
// what a "word" is and on word indexes.

const NUMBER_WORDS: Record<string, string> = {
  '0': 'zero', '1': 'one', '2': 'two', '3': 'three', '4': 'four', '5': 'five',
  '6': 'six', '7': 'seven', '8': 'eight', '9': 'nine', '10': 'ten',
  '11': 'eleven', '12': 'twelve', '13': 'thirteen', '14': 'fourteen',
  '15': 'fifteen', '16': 'sixteen', '17': 'seventeen', '18': 'eighteen',
  '19': 'nineteen', '20': 'twenty',
};

/** Lowercase, straighten quotes, strip punctuation at the edges, spell out 0-20. */
export function normalizeToken(s: string): string {
  let t = s
    .toLowerCase()
    .replace(/[‘’ʼ`]/g, "'")
    .replace(/[‐‑‒]/g, '-');
  t = t.replace(/[^a-z0-9'-]/g, '');
  t = t.replace(/^['-]+|['-]+$/g, '');
  return NUMBER_WORDS[t] ?? t;
}

export interface Token {
  /** The word as printed on the page, punctuation included ("quiet."). */
  display: string;
  /** normalizeToken(display), never empty. */
  norm: string;
}

/**
 * Split text into page words. Index i here is "page word index i" everywhere
 * in the app (alignment, karaoke, PipSentence ranges, planted mistakes).
 */
export function tokenizeDisplay(text: string): Token[] {
  return text
    .replace(/\s*([–—]|--)\s*/g, '$1 ')
    .split(/\s+/)
    .filter(Boolean)
    .map((display) => ({ display, norm: normalizeToken(display) }))
    .filter((t) => t.norm.length > 0);
}

/** Normalized page words, same indexes as tokenizeDisplay. */
export function tokenize(text: string): string[] {
  return tokenizeDisplay(text).map((t) => t.norm);
}

/** Levenshtein distance. */
export function editDistance(a: string, b: string): number {
  if (a === b) return 0;
  if (!a.length) return b.length;
  if (!b.length) return a.length;
  let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
    }
    prev = cur;
  }
  return prev[b.length];
}

/**
 * True when two words should count as the same spoken word.
 * Exact match after normalization (apostrophes ignored), or, for words of 5+
 * characters, an edit distance of 1. That forgives speech-recognition spelling
 * noise on long words but keeps real short-word substitutions (cat/cap) as errors.
 */
export function fuzzyEqual(a: string, b: string): boolean {
  const na = normalizeToken(a).replace(/'/g, '');
  const nb = normalizeToken(b).replace(/'/g, '');
  if (!na || !nb) return false;
  if (na === nb) return true;
  if (Math.min(na.length, nb.length) >= 5 && editDistance(na, nb) <= 1) return true;
  return false;
}
