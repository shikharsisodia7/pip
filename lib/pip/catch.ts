import { fuzzyEqual, tokenize } from '@/lib/text';
import type { PlantedMistake, Transcript } from '@/lib/types';

/** Placeholder: caught if the kid says the correct word anywhere. */
export function detectCatch(transcript: Transcript, mistake: PlantedMistake): boolean {
  const said = transcript.words.length ? transcript.words.map((w) => w.text) : tokenize(transcript.text);
  return said.some((w) => fuzzyEqual(w, mistake.correct));
}
