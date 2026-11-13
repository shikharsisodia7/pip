import { hardestPatternIn, wordsWithPattern } from '@/lib/patterns';
import type { DiagnoseResponse } from '@/lib/types';

// Placeholder: deterministic answer from the page text only.
export async function POST(req: Request) {
  const body = (await req.json().catch(() => ({}))) as { pageText?: string };
  const pageText = body.pageText ?? '';
  const p = hardestPatternIn(pageText);
  const res: DiagnoseResponse = {
    patterns: p
      ? [{
          id: p.id,
          kidLabel: p.kidLabel,
          teacherLabel: p.teacherLabel,
          evidenceWords: wordsWithPattern(pageText, p.id).map((w) => w.word).slice(0, 3),
          confidence: 0.3,
        }]
      : [],
    kidMessage: 'Pip noticed some tricky words. Great reading!',
  };
  return Response.json(res);
}
