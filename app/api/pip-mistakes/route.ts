import { getPattern, hardestPatternIn, wordsWithPattern } from '@/lib/patterns';
import { tokenizeDisplay } from '@/lib/text';
import type { PatternFinding, PipPlan, PipSentence, PlantedMistake } from '@/lib/types';

// Placeholder plan: sentence split plus one naive planted mistake.
export async function POST(req: Request) {
  const body = (await req.json()) as { pageIndex: number; pageText: string; patterns: PatternFinding[] };
  const pageText = body.pageText ?? '';
  const parts = pageText.match(/[^.!?]+[.!?]+["'”’]*|[^.!?]+$/g) ?? [pageText];

  const sentences: PipSentence[] = [];
  let cursor = 0;
  for (const part of parts) {
    const n = tokenizeDisplay(part).length;
    if (!n) continue;
    sentences.push({ index: sentences.length, text: part.trim(), spokenText: part.trim(), wordStart: cursor, wordEnd: cursor + n });
    cursor += n;
  }

  const patternId = body.patterns?.find((p) => getPattern(p.id))?.id ?? hardestPatternIn(pageText)?.id;
  const mistakes: PlantedMistake[] = [];
  if (patternId) {
    const w = wordsWithPattern(pageText, patternId).find((x) => x.index > 0 && x.index < cursor - 1);
    const sentenceIndex = w ? sentences.findIndex((s) => w.index >= s.wordStart && w.index < s.wordEnd) : -1;
    if (w && sentenceIndex >= 0) {
      const misread = w.word.endsWith('ed') ? w.word.slice(0, -2) : w.word.replace(/[aeiou]+/, 'a');
      const s = sentences[sentenceIndex];
      s.spokenText = s.spokenText.replace(w.display.replace(/[^A-Za-z']/g, ''), misread);
      mistakes.push({
        wordIndex: w.index, sentenceIndex, correct: w.word, misread, speakAs: misread,
        patternId, reaction: 'Oh! Thank you, teacher!',
      });
    }
  }

  const plan: PipPlan = { pageIndex: body.pageIndex ?? 1, sentences, mistakes };
  return Response.json(plan);
}
