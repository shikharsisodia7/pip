// Pure helpers that turn realtime Scribe messages into our Transcript shape.
// No React and no network here, so they are unit tested.

import type { TimedWord, Transcript } from '@/lib/types';
import { transcriptFromText } from './mock';

/** A word as Scribe sends it in committed_transcript_with_timestamps. */
export interface ScribeWord {
  text?: string;
  start?: number;
  end?: number;
  type?: 'word' | 'spacing' | 'audio_event';
}

/** One committed segment (manual commit, or the server's ~36 s auto commit). */
export interface ScribeSegment {
  text: string;
  words?: ScribeWord[];
}

const GAP_SEC = 0.3;
const round = (n: number) => Math.round(n * 1000) / 1000;

/** Spoken words only. Fillers like "um" are words and are kept; spacing and audio events are dropped. */
function spoken(words: ScribeWord[] | undefined): ScribeWord[] {
  return (words ?? []).filter(
    (w) => (w.type === undefined || w.type === 'word') && typeof w.text === 'string' && w.text.trim() !== '',
  );
}

/** Evenly spaced synthetic words for text that arrived without timestamps, starting at `from`. */
function synthetic(text: string, from: number): TimedWord[] {
  return transcriptFromText(text).words.map((w) => ({ text: w.text, start: w.start + from, end: w.end + from }));
}

/**
 * Builds the final transcript.
 * - `segments`: committed segments with word timestamps, in arrival order.
 * - `tail`: text heard after the last timestamped segment (the last partial when the
 *   final commit timed out). It gets synthetic, evenly spaced timestamps.
 * - `offsetSec`: where Scribe's audio time 0 sits relative to start().
 *
 * The docs do not say whether word times reset after each commit. If a segment's
 * first word starts before the previous segment ended, it is treated as
 * segment-relative and shifted to follow the previous one.
 */
export function buildTranscript(segments: ScribeSegment[], tail: string, offsetSec: number): Transcript {
  const words: TimedWord[] = [];
  let shift = 0;
  let prevEnd = 0;

  const push = (w: TimedWord) => {
    words.push(w);
    prevEnd = w.end;
  };

  for (const seg of segments) {
    const ws = spoken(seg.words);
    if (ws.length === 0) {
      if (seg.text.trim()) synthetic(seg.text, words.length ? prevEnd + GAP_SEC : 0).forEach(push);
      continue;
    }
    const segStart = ws[0].start ?? prevEnd;
    if (words.length && segStart + shift < prevEnd - 0.05) shift = prevEnd + GAP_SEC - segStart;
    for (const w of ws) {
      const start = (w.start ?? prevEnd) + shift;
      const end = Math.max(start, (w.end ?? w.start ?? prevEnd) + shift);
      push({ text: w.text!.trim(), start, end });
    }
  }

  if (tail.trim()) synthetic(tail, words.length ? prevEnd + GAP_SEC : 0).forEach(push);

  const text = [...segments.map((s) => s.text), tail]
    .map((s) => s.trim())
    .filter(Boolean)
    .join(' ');

  return {
    text,
    words: words.map((w) => ({ text: w.text, start: round(w.start + offsetSec), end: round(w.end + offsetSec) })),
  };
}

/** Running text for live display: everything committed so far plus the current partial. */
export function liveText(committed: string[], partial: string): string {
  return [...committed, partial]
    .map((s) => s.trim())
    .filter(Boolean)
    .join(' ');
}

/**
 * A short, warm sentence for the UI. Microphone errors arrive either as a
 * DOMException (our own permission check) or as a plain message string (the SDK).
 */
export function friendlyListenError(err: unknown): string {
  const name = err instanceof Error || (typeof DOMException !== 'undefined' && err instanceof DOMException) ? err.name : '';
  const msg = err instanceof Error ? err.message : String(err);

  if (/insecure|secure context|mediaDevices/i.test(msg)) {
    return 'The microphone only works on a secure page. Please open the app on localhost or https.';
  }
  if (name === 'NotAllowedError' || name === 'SecurityError' || /permission|not allowed|denied/i.test(msg)) {
    return "Pip can't hear you yet. Please allow the microphone, then try again.";
  }
  if (name === 'NotFoundError' || name === 'OverconstrainedError' || /not found|no microphone/i.test(msg)) {
    return 'No microphone was found. Please plug one in, then try again.';
  }
  if (name === 'NotReadableError' || /could not start|in use/i.test(msg)) {
    return 'The microphone is busy in another app. Please close it, then try again.';
  }
  return "Pip can't listen right now. Please try again.";
}
