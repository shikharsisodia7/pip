'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import Owl from '@/components/pip/Owl';
import { BigButton, Card, MicButton } from '@/components/ui';
import { isMock } from '@/lib/mock';
import { pickProbeWords } from '@/lib/probe';
import { scoreProbe } from '@/lib/probe/score';
import { useListen } from '@/lib/scribe/useListen';
import { useSession } from '@/lib/session';
import { tokenize } from '@/lib/text';
import type { ProbeResult } from '@/lib/types';

type ProbePhase = 'probePre' | 'probePost';
type ProbeSource = 'microphone' | 'mock' | 'sample' | 'skipped';

export default function Probe() {
  const phase = useSession((s) => s.phase);
  if (phase !== 'probePre' && phase !== 'probePost') return null;
  return <ProbeRound key={phase} phase={phase} />;
}

function ProbeRound({ phase }: { phase: ProbePhase }) {
  const [items] = useState(() => pickProbeWords(
    phase === 'probePost' ? 'post' : 'pre',
    useSession.getState().diagnosis?.patterns,
  ));
  const { status, partialText, start, stop } = useListen();
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [failed, setFailed] = useState(false);
  const active = useRef(true);
  const recording = useRef(false);
  const pending = useRef(false);
  const finished = useRef(false);
  const source = useRef<ProbeSource>('microphone');

  const discardRecording = useCallback(() => {
    if (!recording.current) return;
    recording.current = false;
    void stop().catch(() => {});
  }, [stop]);

  useEffect(() => {
    active.current = true;
    return () => {
      active.current = false;
      discardRecording();
    };
  }, [discardRecording]);

  const complete = useCallback((result: ProbeResult | undefined, resultSource: ProbeSource) => {
    const session = useSession.getState();
    if (!active.current || finished.current || session.phase !== phase) return;
    finished.current = true;
    // Preserve provenance for the report/debug panel; a skipped probe has no score.
    session.set({ [phase]: result });
    session.setDebug(`${phase}Source`, resultSource);
    setDone(true);
  }, [phase]);

  const finishReading = useCallback(async () => {
    if (pending.current || finished.current || !recording.current) return;
    pending.current = true;
    setBusy(true);
    try {
      const transcript = await stop();
      recording.current = false;
      complete(scoreProbe(items, transcript), source.current);
    } catch {
      if (active.current) setFailed(true);
    } finally {
      pending.current = false;
      if (active.current) setBusy(false);
    }
  }, [complete, items, stop]);

  const startReading = async () => {
    if (pending.current || finished.current) return;
    pending.current = true;
    recording.current = true;
    source.current = isMock() ? 'mock' : 'microphone';
    setBusy(true);
    setFailed(false);
    try {
      await start();
      if (!active.current || finished.current || useSession.getState().phase !== phase) {
        recording.current = false;
        await stop();
      }
    } catch {
      if (active.current) setFailed(true);
    } finally {
      pending.current = false;
      if (active.current) setBusy(false);
    }
  };

  // One recording for all five words. A short pause finishes it automatically;
  // the stop button remains available for a reading with omitted words.
  useEffect(() => {
    if (status !== 'listening' || busy || done || tokenize(partialText).length < items.length) return;
    const timer = setTimeout(() => void finishReading(), 1400);
    return () => clearTimeout(timer);
  }, [status, busy, done, partialText, items.length, finishReading]);

  useEffect(() => {
    if (!done) return;
    const timer = setTimeout(() => {
      const session = useSession.getState();
      if (session.phase === phase) session.advance();
    }, 1200);
    return () => clearTimeout(timer);
  }, [done, phase]);

  const skip = useCallback(() => {
    complete(undefined, 'skipped');
    discardRecording();
  }, [complete, discardRecording]);

  useEffect(() => {
    const unregister = [2, 4].map((correctCount) => useSession.getState().registerDebugAction(
      `Fill probe ${correctCount}/5`,
      () => {
        complete({
          items: items.map((item, index) => ({ ...item, correct: index < correctCount })),
          correctCount,
        }, 'sample');
        discardRecording();
      },
    ));
    return () => unregister.forEach((remove) => remove());
  }, [complete, discardRecording, items]);

  const listening = status === 'listening';
  const unavailable = busy || status === 'connecting';
  const retry = failed || status === 'error';

  return (
    <main className="mx-auto flex min-h-screen max-w-6xl flex-col items-center justify-center gap-4 px-4 py-4 text-center sm:px-8">
      <Owl state={!done && listening ? 'listening' : 'idle'} size={96} />
      {done ? (
        <h1 className="font-display text-4xl font-semibold sm:text-5xl" role="status">
          Thanks! Pip is ready.
        </h1>
      ) : (
        <>
          <header>
            <h1 className="font-display text-4xl font-semibold">
              {phase === 'probePost' ? 'Five more words for Pip' : 'A little warm up'}
            </h1>
            <p className="mt-3 text-xl text-ink-soft">Tap the mic. Read these words to Pip.</p>
          </header>
          <div className="w-full overflow-x-auto px-1 pb-5 pt-2">
            <ol aria-label="Words to read" className="grid min-w-[720px] grid-cols-5 gap-3 sm:gap-4">
              {items.map((item) => (
                <li key={item.word}>
                  <Card className="flex min-h-32 items-center justify-center border-b-4 border-b-accent-soft px-3">
                    <span className="font-story text-4xl text-ink lg:text-5xl">{item.word}</span>
                  </Card>
                </li>
              ))}
            </ol>
          </div>
          <div className="flex flex-col items-center gap-2">
            <MicButton
              size={88}
              state={unavailable ? 'disabled' : listening ? 'listening' : 'idle'}
              label={unavailable ? 'One moment...' : listening ? 'Pip is listening. Tap when you finish.' : retry ? 'Tap to try again' : 'Tap to read'}
              onClick={() => void (listening ? finishReading() : startReading())}
            />
            <BigButton variant="quiet" size="md" onClick={skip}>Skip for now</BigButton>
          </div>
        </>
      )}
    </main>
  );
}
