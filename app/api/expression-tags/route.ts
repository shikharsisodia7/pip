import type { Emotion, EmotionLine } from '@/lib/types';

const TAGS: Record<Emotion, string> = {
  scared: 'scared', excited: 'excited', sad: 'sad', whispering: 'whispers',
  shouting: 'shouts', happy: 'happy', angry: 'angry',
};

// Placeholder: one tag from a fixed emotion map.
export async function POST(req: Request) {
  const body = (await req.json()) as { line: EmotionLine; context?: string };
  const tag = TAGS[body.line.emotion] ?? 'excited';
  return Response.json({ taggedText: `[${tag}] ${body.line.text}`, tags: [tag] });
}
