// POST /api/tts: Pip's voice.
//
// Every result is cached on disk under .cache/tts/, keyed by text, mode, voice,
// model and settings, so the demo path plays from cache and works offline.
// Mock mode, or a missing key or voice, never calls the network: it serves a
// cached file if one exists, otherwise a short silent placeholder with evenly
// spaced word timings so the UI keeps working.

import { hashKey, readJsonCache, writeCache, writeJsonCache, hasCache } from '@/lib/server/cache';
import { isMockRequest } from '@/lib/mock';
import { evenTimings, wordsFromAlignment, type CharAlignment } from '@/lib/pip/alignment';
import { presetFor, stripAudioTags } from '@/lib/pip/voice';
import type { TimedWord, TtsRequest, TtsResponse } from '@/lib/types';

export const runtime = 'nodejs';

const API = 'https://api.elevenlabs.io/v1/text-to-speech';

interface CachedMeta { words?: TimedWord[]; ext: string }

function audioUrl(id: string) {
  return `/api/tts/audio/${id}`;
}

/** A silent 16 kHz mono WAV of the given length. Only ever written to .cache/. */
function silentWav(seconds: number): Buffer {
  const rate = 16000;
  const n = Math.max(1, Math.round(seconds * rate));
  const buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(rate, 24); buf.writeUInt32LE(rate * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(n * 2, 40);
  return buf;
}

async function placeholder(text: string, mode: TtsRequest['mode']): Promise<TtsResponse> {
  const words = evenTimings(stripAudioTags(text));
  const seconds = words.length ? words[words.length - 1].end + 0.3 : 1;
  const id = `placeholder-${Math.round(seconds * 10)}`;
  if (!(await hasCache('tts', id, '.wav'))) await writeCache('tts', id, silentWav(seconds), '.wav');
  return { audioUrl: audioUrl(id), words: mode === 'flat' ? words : undefined };
}

export async function POST(req: Request) {
  let body: TtsRequest;
  try {
    body = (await req.json()) as TtsRequest;
  } catch {
    return Response.json({ error: 'bad json' }, { status: 400 });
  }
  const text = (body.text ?? '').trim();
  const mode = body.mode === 'expressive' ? 'expressive' : 'flat';
  if (!text) return Response.json({ error: 'empty text' }, { status: 400 });

  const preset = presetFor({ mode });
  const voiceId = process.env.PIP_VOICE_ID ?? '';
  const key = hashKey('tts-v1', text, mode, voiceId, preset.modelId, preset.voiceSettings);

  const meta = await readJsonCache<CachedMeta>('tts', key);
  if (meta && (await hasCache('tts', key, meta.ext))) {
    return Response.json({ audioUrl: audioUrl(key), words: meta.words } satisfies TtsResponse);
  }

  const apiKey = process.env.ELEVENLABS_API_KEY;
  if (isMockRequest(req) || !apiKey || !voiceId) {
    return Response.json(await placeholder(text, mode));
  }

  try {
    const url = `${API}/${encodeURIComponent(voiceId)}${preset.withTimestamps ? '/with-timestamps' : ''}?output_format=mp3_44100_128`;
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'xi-api-key': apiKey, 'content-type': 'application/json' },
      body: JSON.stringify({ text, model_id: preset.modelId, voice_settings: preset.voiceSettings }),
    });
    if (!res.ok) throw new Error(`ElevenLabs ${res.status}: ${(await res.text()).slice(0, 300)}`);

    let audio: Buffer;
    let words: TimedWord[] | undefined;
    if (preset.withTimestamps) {
      const json = (await res.json()) as { audio_base64: string; alignment?: CharAlignment };
      audio = Buffer.from(json.audio_base64, 'base64');
      words = wordsFromAlignment(text, json.alignment);
    } else {
      audio = Buffer.from(await res.arrayBuffer());
    }

    await writeCache('tts', key, audio, '.mp3');
    await writeJsonCache('tts', key, { words, ext: '.mp3' } satisfies CachedMeta);
    return Response.json({ audioUrl: audioUrl(key), words } satisfies TtsResponse);
  } catch (err) {
    console.error('[tts] falling back to placeholder:', String(err));
    return Response.json(await placeholder(text, mode));
  }
}
