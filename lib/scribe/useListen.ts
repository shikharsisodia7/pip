'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import type { Transcript } from '@/lib/types';
import { peekMockTranscript, takeMockTranscript } from './mock';

export interface ListenApi {
  status: 'idle' | 'connecting' | 'listening' | 'error';
  partialText: string;                 // live, for karaoke and live catch feedback
  start(): Promise<void>;              // opens mic, mints a fresh token
  stop(): Promise<Transcript>;         // closes mic, resolves with committed words + timestamps
  error?: string;
}

/**
 * Listening hook. Callers only ever use this interface.
 * The skeleton ships the mock only: it "hears" the transcript queued with
 * injectMockTranscript() (default: the page 1 demo reading) and reveals its
 * words as partials at their timestamps, so karaoke works offline.
 * The live ElevenLabs Scribe implementation is selected inside this hook.
 */
export function useListen(): ListenApi {
  return useMockListen();
}

function useMockListen(): ListenApi {
  const [status, setStatus] = useState<ListenApi['status']>('idle');
  const [partialText, setPartialText] = useState('');
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);

  const clearTimers = () => {
    timers.current.forEach(clearTimeout);
    timers.current = [];
  };
  useEffect(() => clearTimers, []);

  const start = useCallback(async () => {
    clearTimers();
    setPartialText('');
    setStatus('connecting');
    await new Promise((r) => setTimeout(r, 150));
    setStatus('listening');
    const t = peekMockTranscript();
    t.words.forEach((w, i) => {
      timers.current.push(
        setTimeout(() => setPartialText(t.words.slice(0, i + 1).map((x) => x.text).join(' ')), w.end * 1000),
      );
    });
  }, []);

  const stop = useCallback(async () => {
    clearTimers();
    setStatus('idle');
    const t = takeMockTranscript();
    setPartialText(t.text);
    return t;
  }, []);

  return { status, partialText, start, stop };
}
