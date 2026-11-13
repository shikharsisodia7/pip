import type { PatternFinding, PracticeBook } from '@/lib/types';

// Placeholder practice book.
export async function POST(req: Request) {
  const body = (await req.json().catch(() => ({}))) as { pattern?: PatternFinding };
  const pattern: PatternFinding = body.pattern ?? {
    id: 'ough', kidLabel: "the 'ough' sound", teacherLabel: 'vowel team: ough', evidenceWords: [], confidence: 0,
  };
  const res: PracticeBook = {
    title: "Pip's Practice Book",
    pattern,
    sentences: [
      'Pip sat in a tall tree.',
      'He looked at the moon.',
      'He thought about his book.',
      'He read a page out loud.',
      'He read it one more time.',
      'Then Pip went to sleep.',
    ],
  };
  return Response.json(res);
}
