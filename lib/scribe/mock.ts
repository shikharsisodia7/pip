// Mock listener input. The debug panel calls injectMockTranscript(); the mock
// useListen() "hears" it on the next start()/stop(). Keep these exports stable:
// components/debug depends on them.

import page1 from '@/fixtures/transcripts/page1-demo.json';
import type { Transcript } from '@/lib/types';

const DEFAULT_TRANSCRIPT = page1 as Transcript;

let queued: Transcript | null = null;

/** Evenly spaced synthetic timestamps for typed text. */
export function transcriptFromText(text: string, wordsPerSec = 2.2): Transcript {
  const words = text
    .split(/\s+/)
    .filter(Boolean)
    .map((w, i) => ({
      text: w,
      start: Math.round((i / wordsPerSec) * 100) / 100,
      end: Math.round(((i + 0.8) / wordsPerSec) * 100) / 100,
    }));
  return { text: text.trim(), words };
}

/** Queue what the mock listener hears next (used once, then cleared). */
export function injectMockTranscript(input: string | Transcript): void {
  queued = typeof input === 'string' ? transcriptFromText(input) : input;
}

export function clearMockTranscript(): void {
  queued = null;
}

/** What the next mock listen will hear, without consuming it. */
export function peekMockTranscript(): Transcript {
  return queued ?? DEFAULT_TRANSCRIPT;
}

/** Consume the queued transcript (falls back to the page 1 demo reading). */
export function takeMockTranscript(): Transcript {
  const t = peekMockTranscript();
  queued = null;
  return t;
}
