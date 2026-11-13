import { tokenizeDisplay } from '@/lib/text';
import type { TtsRequest, TtsResponse } from '@/lib/types';

// Placeholder: no audio, evenly spaced word timings so highlighting can be built.
export async function POST(req: Request) {
  const body = (await req.json()) as TtsRequest;
  const plain = body.text.replace(/\[[^\]]*\]/g, ' ');
  const words = tokenizeDisplay(plain).map((t, i) => ({
    text: t.display,
    start: Math.round(i * 0.4 * 100) / 100,
    end: Math.round((i * 0.4 + 0.32) * 100) / 100,
  }));
  const res: TtsResponse = { audioUrl: '', words: body.mode === 'flat' ? words : undefined };
  return Response.json(res);
}
