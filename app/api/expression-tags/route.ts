// POST /api/expression-tags: chooses 1 or 2 eleven_v3 audio tags for an
// emotional line and inserts them, so Pip can perform it with feeling.
// Claude picks from a fixed allowlist; anything invalid falls back to a
// deterministic emotion map. This route never fails.

import { z } from 'zod';
import { claudeJson } from '@/lib/server/claudeJson';
import { isMockRequest } from '@/lib/mock';
import type { Emotion, EmotionLine } from '@/lib/types';

const ALLOWED = [
  'scared', 'nervous', 'gasps', 'excited', 'happy', 'laughs', 'sad', 'sighs',
  'whispers', 'shouts', 'angry', 'surprised', 'curious', 'crying',
] as const;

const FALLBACK: Record<Emotion, string[]> = {
  scared: ['gasps', 'scared'],
  excited: ['excited'],
  sad: ['sad'],
  whispering: ['whispers'],
  shouting: ['shouts'],
  happy: ['happy'],
  angry: ['angry'],
};

const Schema = z.object({ taggedText: z.string().min(1), tags: z.array(z.string()).min(1).max(2) });
type TagResult = z.infer<typeof Schema>;

const plain = (s: string) =>
  s.replace(/\[[^\]]*\]/g, ' ').toLowerCase().replace(/[^a-z0-9']+/g, ' ').trim();

function fallback(line: EmotionLine): TagResult {
  const tags = FALLBACK[line.emotion] ?? ['excited'];
  return { taggedText: `${tags.map((t) => `[${t}]`).join(' ')} ${line.text}`, tags };
}

function valid(result: TagResult, line: EmotionLine): boolean {
  const used = [...result.taggedText.matchAll(/\[([^\]]+)\]/g)].map((m) => m[1].trim().toLowerCase());
  return (
    used.length >= 1 && used.length <= 2 &&
    used.every((t) => (ALLOWED as readonly string[]).includes(t)) &&
    plain(result.taggedText) === plain(line.text)
  );
}

export async function POST(req: Request) {
  let line: EmotionLine;
  let context = '';
  try {
    const body = (await req.json()) as { line: EmotionLine; context?: string };
    line = body.line;
    context = body.context ?? '';
    if (!line?.text) throw new Error('missing line');
  } catch {
    return Response.json({ error: 'bad request' }, { status: 400 });
  }

  try {
    const result = await claudeJson<TagResult>({
      name: 'expression-tags',
      fixture: 'fixtures/pip/expression-tags.json',
      mock: isMockRequest(req),
      schema: Schema,
      maxTokens: 300,
      system:
        'You direct a text-to-speech voice actor for a children\'s picture book. ' +
        'You add inline audio tags in square brackets to a line so it is performed with the right feeling.',
      prompt: [
        `Line: ${JSON.stringify(line.text)}`,
        `Speaker: ${line.speaker ?? 'unknown'}`,
        `Emotion: ${line.emotion}`,
        context ? `Story context: ${JSON.stringify(context)}` : '',
        `Allowed tags: ${ALLOWED.join(', ')}.`,
        'Insert 1 or 2 allowed tags into the line (usually at the start, optionally one mid-line before a phrase).',
        'Do not change, add or remove any words or punctuation of the line.',
        'Return {"taggedText": string, "tags": string[]}.',
      ].filter(Boolean).join('\n'),
    });
    if (valid(result, line)) {
      const tags = [...result.taggedText.matchAll(/\[([^\]]+)\]/g)].map((m) => m[1].trim().toLowerCase());
      return Response.json({ taggedText: result.taggedText, tags });
    }
  } catch (err) {
    console.warn('[expression-tags] using fallback:', String(err).slice(0, 200));
  }
  return Response.json(fallback(line));
}
