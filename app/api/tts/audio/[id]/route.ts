// GET /api/tts/audio/:id serves cached Pip audio from .cache/tts/.
// Files are content-addressed, so they can be cached by the browser forever.

import { readCache } from '@/lib/server/cache';

export const runtime = 'nodejs';

const TYPES: Record<string, string> = { '.mp3': 'audio/mpeg', '.wav': 'audio/wav' };

export async function GET(_req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  if (!/^[a-z0-9-]{1,64}$/.test(id)) return new Response('not found', { status: 404 });
  for (const ext of Object.keys(TYPES)) {
    const buf = await readCache('tts', id, ext);
    if (buf) {
      return new Response(new Uint8Array(buf), {
        headers: {
          'content-type': TYPES[ext],
          'content-length': String(buf.length),
          'cache-control': 'public, max-age=31536000, immutable',
        },
      });
    }
  }
  return new Response('not found', { status: 404 });
}
