'use client';

// Client helpers for Pip's voice.
// speak() asks /api/tts for a line and also downloads the audio into a blob URL,
// so playback starts instantly and keeps working if the network drops later.
// Identical requests share one in-flight promise.

import { postJson } from '@/lib/api';
import type { TtsRequest, TtsResponse } from '@/lib/types';

const responses = new Map<string, Promise<TtsResponse>>();

function keyOf(req: TtsRequest): string {
  return `${req.mode}|${req.text}`;
}

async function fetchLine(req: TtsRequest): Promise<TtsResponse> {
  const resp = await postJson<TtsResponse>('/api/tts', req);
  if (!resp.audioUrl || resp.audioUrl.startsWith('blob:')) return resp;
  try {
    const audio = await fetch(resp.audioUrl);
    if (!audio.ok) return resp;
    const blobUrl = URL.createObjectURL(await audio.blob());
    return { ...resp, audioUrl: blobUrl };
  } catch {
    return resp;
  }
}

export function speak(req: TtsRequest): Promise<TtsResponse> {
  const k = keyOf(req);
  let p = responses.get(k);
  if (!p) {
    p = fetchLine(req).catch((err) => {
      responses.delete(k);
      throw err;
    });
    responses.set(k, p);
  }
  return p;
}

/** Warms several lines, three at a time. Never throws. */
export async function prefetch(reqs: TtsRequest[]): Promise<void> {
  const queue = [...reqs];
  const worker = async () => {
    while (queue.length) {
      const next = queue.shift()!;
      await speak(next).catch(() => undefined);
    }
  };
  await Promise.all([worker(), worker(), worker()]);
}

export const flat = (text: string): TtsRequest => ({ text, mode: 'flat', withTimestamps: true });
export const expressive = (text: string): TtsRequest => ({ text, mode: 'expressive' });
