// POST /api/pip-mistakes: plans Pip's read-back of a page with planted mistakes.
//
// Which words Pip misreads, and every index, is decided deterministically in
// lib/pip/reads-plan.ts. Claude only writes the creative part for those words:
// a child-realistic misreading, a spelling TTS will pronounce, and Pip's
// in-character reaction. Everything Claude returns is validated, and anything
// missing falls back to the per-pattern table. This route never fails.

import { z } from 'zod';
import { claudeJson } from '@/lib/server/claudeJson';
import { isMockRequest } from '@/lib/mock';
import { getPattern } from '@/lib/patterns';
import { buildPlan, type MistakeWording, type PlanRequest } from '@/lib/pip/reads-plan';

const Schema = z.object({
  mistakes: z.array(z.object({
    correct: z.string(),
    misread: z.string(),
    speakAs: z.string(),
    reaction: z.string(),
  })),
});

export async function POST(req: Request) {
  let body: PlanRequest;
  try {
    body = (await req.json()) as PlanRequest;
  } catch {
    return Response.json({ error: 'bad json' }, { status: 400 });
  }
  const request: PlanRequest = {
    pageIndex: Number(body.pageIndex ?? 1),
    pageText: String(body.pageText ?? ''),
    patterns: Array.isArray(body.patterns) ? body.patterns : [],
    count: body.count,
    emotionLineText: body.emotionLineText,
  };

  // Deterministic plan first: it fixes the words and is the fallback.
  const base = buildPlan(request);
  if (!base.mistakes.length) return Response.json(base);

  let wordings: MistakeWording[] = [];
  try {
    const targets = base.mistakes.map((m) => ({
      correct: m.correct,
      pattern: getPattern(m.patternId)?.teacherLabel ?? m.patternId,
      sentence: base.sentences[m.sentenceIndex]?.text ?? '',
    }));
    const result = await claudeJson({
      name: 'pip-mistakes',
      fixture: 'fixtures/pip/pip-mistakes.json',
      mock: isMockRequest(req),
      schema: Schema,
      maxTokens: 600,
      system:
        'You write lines for Pip, a friendly cartoon owl who is learning to read. A child is his teacher. ' +
        'Pip makes the kind of decoding mistake a real beginning reader makes on a phonics pattern.',
      prompt: [
        'For each target word, return:',
        '- misread: how a beginning reader would wrongly decode it, based on the pattern (for example dropping -ed, reading a vowel team as a short vowel, ignoring silent e). It must clearly differ from the correct word and must not be a real word that also makes sense in the sentence.',
        '- speakAs: a spelling of the misread word that a text to speech voice will pronounce as intended (often the same as misread).',
        '- reaction: what Pip says, warmly and briefly, when the child catches the mistake. Under 12 words, mention the correct word, no em dashes.',
        `Targets: ${JSON.stringify(targets)}`,
        'Return {"mistakes": [{"correct", "misread", "speakAs", "reaction"}]} in the same order.',
      ].join('\n'),
    });
    wordings = result.mistakes;
  } catch (err) {
    console.warn('[pip-mistakes] using fallback wording:', String(err).slice(0, 200));
  }

  return Response.json(buildPlan(request, wordings));
}
