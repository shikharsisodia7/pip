'use client';

// Plays Pip's audio and fires a callback as each word starts, for highlighting.
// Only one line plays at a time. isSpeaking() is the gate that keeps the mic
// closed while Pip talks (contract rule 9.1).

import { useSyncExternalStore } from 'react';
import type { TtsResponse } from '@/lib/types';

let speaking = false;
let current: PlayHandle | null = null;
const listeners = new Set<() => void>();

function setSpeaking(v: boolean) {
  if (speaking === v) return;
  speaking = v;
  listeners.forEach((l) => l());
}

/** True while Pip is talking. The mic must never open while this is true. */
export function isSpeaking(): boolean {
  return speaking;
}

/** React hook version of isSpeaking(). */
export function useIsSpeaking(): boolean {
  return useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    () => speaking,
    () => false,
  );
}

export interface PlayHandle {
  stop(): void;
  done: Promise<void>;
}

export interface PlayOptions {
  onWord?: (i: number) => void;
  onEnd?: () => void;
}

/** Stops whatever Pip is saying right now. */
export function stopSpeaking(): void {
  current?.stop();
}

export function play(resp: TtsResponse, opts: PlayOptions = {}): PlayHandle {
  current?.stop();

  const words = resp.words ?? [];
  let ended = false;
  let raf = 0;
  let nextWord = 0;
  const timers: ReturnType<typeof setTimeout>[] = [];
  let resolveDone: () => void = () => {};
  const done = new Promise<void>((r) => (resolveDone = r));
  const audio = resp.audioUrl ? new Audio(resp.audioUrl) : null;

  const finish = () => {
    if (ended) return;
    ended = true;
    cancelAnimationFrame(raf);
    timers.forEach(clearTimeout);
    if (audio) {
      audio.onended = null;
      audio.onerror = null;
      audio.pause();
    }
    // Flush any words not yet highlighted so the sentence ends fully lit.
    while (nextWord < words.length) opts.onWord?.(nextWord++);
    if (current === handle) current = null;
    setSpeaking(false);
    opts.onEnd?.();
    resolveDone();
  };

  // Timer-driven fallback when there is no playable audio.
  const runWithTimers = () => {
    words.forEach((w, i) =>
      timers.push(setTimeout(() => {
        if (!ended && i >= nextWord) {
          nextWord = i + 1;
          opts.onWord?.(i);
        }
      }, w.start * 1000)),
    );
    const totalMs = words.length ? words[words.length - 1].end * 1000 + 200 : 800;
    timers.push(setTimeout(finish, totalMs));
  };

  const tick = () => {
    if (ended || !audio) return;
    const t = audio.currentTime;
    while (nextWord < words.length && t >= words[nextWord].start) opts.onWord?.(nextWord++);
    raf = requestAnimationFrame(tick);
  };

  const handle: PlayHandle = { stop: finish, done };
  current = handle;
  setSpeaking(true);

  if (!audio) {
    runWithTimers();
  } else {
    audio.onended = finish;
    audio.onerror = () => {
      if (!ended && audio.currentTime === 0) runWithTimers();
      else finish();
    };
    audio.play().then(
      () => {
        raf = requestAnimationFrame(tick);
      },
      () => {
        // Autoplay blocked or decode failure: keep the UI moving.
        if (!ended) runWithTimers();
      },
    );
    // Safety net in case the audio element never reports an end.
    const safetyMs = (words.length ? words[words.length - 1].end : 8) * 1000 + 4000;
    timers.push(setTimeout(finish, Math.max(safetyMs, 6000)));
  }

  return handle;
}

/** Convenience: play and wait until Pip finishes. */
export function playAndWait(resp: TtsResponse, opts: PlayOptions = {}): Promise<void> {
  return play(resp, opts).done;
}
