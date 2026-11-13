import { postJson } from '@/lib/api';
import type { TtsRequest, TtsResponse } from '@/lib/types';

/** Placeholder client helper for /api/tts. */
export function speak(req: TtsRequest): Promise<TtsResponse> {
  return postJson<TtsResponse>('/api/tts', req);
}

export async function prefetch(reqs: TtsRequest[]): Promise<void> {
  await Promise.all(reqs.map((r) => speak(r).catch(() => undefined)));
}
