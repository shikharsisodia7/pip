// Voice presets for Pip. Shared by the TTS route and the cache key, so changing a
// preset automatically produces fresh audio instead of serving stale cache.
//
// Flat Pip (reading back a page) must sound monotone and robotic, and needs word
// timestamps for highlighting, so it uses a non-v3 model on the with-timestamps
// endpoint with maximum stability and no style. Measured on the Pip voice,
// eleven_turbo_v2_5 at these settings had about a quarter of the pitch movement of
// eleven_multilingual_v2.
//
// Expressive Pip (the learned line, and his conversational lines) uses eleven_v3,
// which understands inline audio tags such as [excited] or [whispers]. Timestamps
// are not requested from v3.

import type { TtsRequest } from '@/lib/types';

export interface VoicePreset {
  modelId: string;
  withTimestamps: boolean;
  voiceSettings: Record<string, number | boolean>;
}

export const FLAT_PRESET: VoicePreset = {
  modelId: 'eleven_turbo_v2_5',
  withTimestamps: true,
  voiceSettings: { stability: 1, similarity_boost: 0.75, style: 0, use_speaker_boost: false, speed: 0.9 },
};

export const EXPRESSIVE_PRESET: VoicePreset = {
  modelId: 'eleven_v3',
  withTimestamps: false,
  // v3 stability is one of 0 (creative), 0.5 (natural), 1 (robust). Creative is the
  // most responsive to audio tags, which is the whole point of the reveal.
  voiceSettings: { stability: 0 },
};

export function presetFor(req: Pick<TtsRequest, 'mode'>): VoicePreset {
  return req.mode === 'expressive' ? EXPRESSIVE_PRESET : FLAT_PRESET;
}

/** Strips v3 audio tags like [excited] for display and timing estimates. */
export function stripAudioTags(text: string): string {
  return text.replace(/\[[^\]]*\]/g, ' ').replace(/\s+/g, ' ').trim();
}
