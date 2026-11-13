/**
 * Prosody recorder (contract 7.2).
 *
 * The recorder opens its own getUserMedia stream, separate from the
 * speech-to-text stream. This is intended: browsers allow several captures of
 * the same microphone, and keeping them independent means neither side has to
 * coordinate with the other.
 *
 * SSR safety: nothing here touches window, navigator or AudioContext at import
 * time. All browser access happens inside start().
 */
import type { ProsodyFrame, ProsodyStats } from '@/lib/types';
import {
  FRAME_SIZE,
  ProsodyTracker,
  analyzeFrame,
  createDetector,
  emptyStats,
  type FramePitchDetector,
} from './analysis';

export * from './analysis';
export * from './score';

export interface ProsodyRecorder {
  start(): Promise<void>;
  stop(): Promise<ProsodyStats>;
  onFrame(cb: (f: ProsodyFrame) => void): () => void; // returns unsubscribe
}

/** Polling interval for the analyser, in milliseconds. */
export const POLL_INTERVAL_MS = 25;

type AudioContextCtor = typeof AudioContext;

function getAudioContextCtor(): AudioContextCtor | null {
  if (typeof window === 'undefined') return null;
  const w = window as unknown as { AudioContext?: AudioContextCtor; webkitAudioContext?: AudioContextCtor };
  return w.AudioContext ?? w.webkitAudioContext ?? null;
}

interface ActiveSession {
  stream: MediaStream;
  ctx: AudioContext;
  source: MediaStreamAudioSourceNode;
  analyser: AnalyserNode;
  timer: ReturnType<typeof setInterval>;
}

export function createProsodyRecorder(): ProsodyRecorder {
  const subscribers = new Set<(f: ProsodyFrame) => void>();
  const tracker = new ProsodyTracker();
  let detector: FramePitchDetector | null = null;
  let active: ActiveSession | null = null;
  let starting: Promise<void> | null = null;

  function emit(frame: ProsodyFrame): void {
    for (const cb of subscribers) {
      try {
        cb(frame);
      } catch (err) {
        console.error('[prosody] onFrame subscriber threw', err);
      }
    }
  }

  async function open(): Promise<void> {
    const Ctor = getAudioContextCtor();
    if (!Ctor || typeof navigator === 'undefined' || !navigator.mediaDevices?.getUserMedia) {
      throw new Error('Microphone capture is not available in this environment');
    }

    const stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: true,
        noiseSuppression: true,
        // Gain control would flatten the loudness variation we are measuring.
        autoGainControl: false,
      },
    });

    let ctx: AudioContext;
    try {
      ctx = new Ctor();
      if (ctx.state === 'suspended') await ctx.resume();
    } catch (err) {
      stream.getTracks().forEach((t) => t.stop());
      throw err;
    }

    const source = ctx.createMediaStreamSource(stream);
    const analyser = ctx.createAnalyser();
    analyser.fftSize = FRAME_SIZE;
    analyser.smoothingTimeConstant = 0;
    // Not connected to the destination, so the microphone is never played back.
    source.connect(analyser);

    if (!detector || detector.inputLength !== analyser.fftSize) {
      detector = createDetector(analyser.fftSize);
    }
    const det = detector;
    const buffer = new Float32Array(analyser.fftSize);
    const sampleRate = ctx.sampleRate;
    const t0 = performance.now();
    tracker.reset();

    // setInterval rather than requestAnimationFrame: rAF stops entirely in a
    // background tab, while timers keep firing (possibly throttled). The
    // tracker works from timestamps, so a slower poll only reduces resolution.
    const timer = setInterval(() => {
      analyser.getFloatTimeDomainData(buffer);
      const t = (performance.now() - t0) / 1000;
      emit(tracker.push(t, analyzeFrame(buffer, sampleRate, det)));
    }, POLL_INTERVAL_MS);

    active = { stream, ctx, source, analyser, timer };
  }

  async function close(session: ActiveSession): Promise<void> {
    clearInterval(session.timer);
    session.stream.getTracks().forEach((t) => t.stop());
    try {
      session.source.disconnect();
    } catch {
      // Already disconnected.
    }
    try {
      if (session.ctx.state !== 'closed') await session.ctx.close();
    } catch {
      // Closing a context that is already closing is harmless.
    }
  }

  return {
    start(): Promise<void> {
      if (active) return Promise.resolve();
      if (starting) return starting;
      starting = open().finally(() => {
        starting = null;
      });
      return starting;
    },

    async stop(): Promise<ProsodyStats> {
      if (starting) {
        try {
          await starting;
        } catch {
          // start() failed; there is nothing to stop.
        }
      }
      const session = active;
      if (!session) return emptyStats();
      active = null;
      await close(session);
      const stats = tracker.finish();
      tracker.reset();
      return stats;
    },

    onFrame(cb: (f: ProsodyFrame) => void): () => void {
      subscribers.add(cb);
      return () => {
        subscribers.delete(cb);
      };
    },
  };
}
