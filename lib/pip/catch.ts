// Did the child catch Pip's mistake? Plain string matching, no model (contract 9.6).

import { fuzzyEqual, normalizeToken, tokenize } from '@/lib/text';
import type { PlantedMistake, Transcript } from '@/lib/types';

/** Every normalized word the child said, from the timed words and the text. */
function saidTokens(transcript: Transcript | null | undefined): string[] {
  if (!transcript) return [];
  const fromWords = (transcript.words ?? []).flatMap((w) => tokenize(w.text ?? ''));
  const fromText = tokenize(transcript.text ?? '');
  return fromWords.length >= fromText.length ? fromWords : fromText;
}

/**
 * True when the child said the correct word anywhere ("thought",
 * "no, it says thought"). Saying Pip's misreading back does not count.
 */
export function detectCatch(transcript: Transcript | null | undefined, mistake: PlantedMistake): boolean {
  const misread = normalizeToken(mistake.misread ?? '');
  return saidTokens(transcript).some((w) => w !== misread && fuzzyEqual(w, mistake.correct));
}

const OBJECTION_WORDS = new Set([
  'no', 'nope', 'nah', 'wrong', 'not', 'incorrect', 'oops', 'mistake', 'uh-uh', 'nuh-uh', 'wait', 'again',
]);
const OBJECTION_PHRASES = [/\bthat'?s not right\b/, /\btry again\b/, /\byou got it wrong\b/, /\bmixed (it|one) up\b/];

/**
 * True for "no", "that's wrong", "wrong", "nope" said without the right word.
 * Pass the mistake to make sure a real catch never counts as a bare objection.
 */
export function isBareObjection(transcript: Transcript | null | undefined, mistake?: PlantedMistake): boolean {
  const tokens = saidTokens(transcript);
  if (!tokens.length) return false;
  if (mistake && detectCatch(transcript, mistake)) return false;
  if (tokens.some((t) => OBJECTION_WORDS.has(t))) return true;
  const text = tokens.join(' ');
  return OBJECTION_PHRASES.some((re) => re.test(text));
}
