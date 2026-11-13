import type { TtsResponse } from '@/lib/types';

let speaking = false;

/** True while Pip is talking. The mic must never open while this is true. */
export function isSpeaking(): boolean {
  return speaking;
}

export interface PlayHandle {
  stop(): void;
  done: Promise<void>;
}

/** Placeholder player: fires word callbacks from the timings, no audio yet. */
export function play(
  resp: TtsResponse,
  opts: { onWord?: (i: number) => void; onEnd?: () => void } = {},
): PlayHandle {
  speaking = true;
  let ended = false;
  const timers: ReturnType<typeof setTimeout>[] = [];
  let resolveDone: () => void = () => {};
  const done = new Promise<void>((r) => (resolveDone = r));
  const finish = () => {
    if (ended) return;
    ended = true;
    speaking = false;
    timers.forEach(clearTimeout);
    opts.onEnd?.();
    resolveDone();
  };
  const words = resp.words ?? [];
  words.forEach((w, i) => timers.push(setTimeout(() => opts.onWord?.(i), w.start * 1000)));
  const totalMs = words.length ? words[words.length - 1].end * 1000 + 200 : 800;
  timers.push(setTimeout(finish, totalMs));
  return { stop: finish, done };
}
