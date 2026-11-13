'use client';

// The child reads page 1 aloud to Pip. Words light up as they are heard, then
// Pip shares what it noticed and the child hands the book over to Pip.

import { AnimatePresence, motion } from 'framer-motion';
import { useEffect, useEffectEvent, useMemo, useRef, useState } from 'react';
import Owl, { type OwlState } from '@/components/pip/Owl';
import NoticedCard from '@/components/read/NoticedCard';
import StoryBook from '@/components/read/StoryBook';
import { advanceCursor, INITIAL_CURSOR, matchForward, type CursorState } from '@/components/read/karaoke';
import { MicButton, StoryCredit } from '@/components/ui';
import { postJson } from '@/lib/api';
import { DEMO_PAGE1_TRANSCRIPT } from '@/lib/demo/script';
import { createProsodyRecorder } from '@/lib/prosody';
import { alignWords } from '@/lib/reading/align';
import { computeMetrics } from '@/lib/reading/metrics';
import { useListen } from '@/lib/scribe/useListen';
import { useSession } from '@/lib/session';
import { fuzzyEqual, tokenize, tokenizeDisplay } from '@/lib/text';
import type { DiagnoseResponse, ProsodyStats, Transcript } from '@/lib/types';

type Stage = 'ready' | 'starting' | 'listening' | 'thinking' | 'done';

/** Pip thinks for at least this long so the moment reads, and never longer than the max. */
const MIN_THINK_MS = 900;
const MAX_THINK_MS = 2000;
/** How long stopping waits for a pitch recorder that is still starting (for example, behind a mic prompt). */
const RECORDER_GRACE_MS = 400;

const OWL_FOR_STAGE: Record<Stage, OwlState> = {
  ready: 'idle',
  starting: 'listening',
  listening: 'listening',
  thinking: 'thinking',
  done: 'celebrating',
};

const wait = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

const isDiagnosis = (d: unknown): d is DiagnoseResponse =>
  !!d && Array.isArray((d as DiagnoseResponse).patterns) && typeof (d as DiagnoseResponse).kidMessage === 'string';

export default function Read() {
  const book = useSession((s) => s.book);
  const page = useSession((s) => s.book.pages[s.readPageIndex]);
  const diagnosis = useSession((s) => s.diagnosis);
  const set = useSession((s) => s.set);
  const advance = useSession((s) => s.advance);
  const registerDebugAction = useSession((s) => s.registerDebugAction);

  const listen = useListen();
  const [recorder] = useState(createProsodyRecorder);

  const words = useMemo(() => tokenizeDisplay(page.text), [page.text]);
  const norms = useMemo(() => words.map((w) => w.norm), [words]);

  const [stage, setStage] = useState<Stage>('ready');
  const [karaoke, setKaraoke] = useState<{ partial: string; cursor: CursorState }>({ partial: '', cursor: INITIAL_CURSOR });
  const [finalCount, setFinalCount] = useState(0);

  const runRef = useRef(0);
  const listeningRef = useRef(false);
  /** Resolves true once the pitch recorder is running; null when it is not in use. */
  const recorderRef = useRef<Promise<boolean> | null>(null);
  const listenRef = useRef(listen);
  useEffect(() => {
    listenRef.current = listen;
  });

  // Follow the live transcript while listening (state derived during render).
  if (stage === 'listening' && karaoke.partial !== listen.partialText) {
    setKaraoke({ partial: listen.partialText, cursor: advanceCursor(karaoke.cursor, norms, listen.partialText) });
  }

  // A mic problem drops back to the mic button with a gentle retry.
  const micTrouble = listen.status === 'error' && (stage === 'starting' || stage === 'listening');
  const shown: Stage = micTrouble ? 'ready' : stage;

  const readCount =
    shown === 'listening' ? karaoke.cursor.cursor
    : shown === 'thinking' || shown === 'done' ? Math.max(karaoke.cursor.cursor, finalCount)
    : 0;
  const currentIndex = shown === 'listening' && readCount < words.length ? readCount : null;

  const underlined = useMemo(() => {
    const top = diagnosis?.patterns?.[0];
    if (shown !== 'done' || !top) return undefined;
    return new Set(
      words.flatMap((w, i) => (top.evidenceWords.some((e) => fuzzyEqual(e, w.norm)) ? [i] : [])),
    );
  }, [diagnosis, shown, words]);

  // The pitch recorder runs alongside listening but never holds it up: the
  // child can read even if it is slow to start or never gets the mic.
  function startRecorder() {
    recorderRef.current = recorder.start().then(() => true, () => false);
  }

  async function stopRecorder(): Promise<ProsodyStats | null> {
    const starting = recorderRef.current;
    recorderRef.current = null;
    if (!starting) return null;
    const started = await Promise.race([starting, wait(RECORDER_GRACE_MS).then(() => null)]);
    if (started === null) {
      // Still starting: close it as soon as it opens, and read on without it.
      void starting.then((ok) => {
        if (ok) recorder.stop().catch(() => {});
      });
      return null;
    }
    return started ? recorder.stop().catch(() => null) : null;
  }

  async function stopListening(): Promise<Transcript | null> {
    if (!listeningRef.current) return null;
    listeningRef.current = false;
    return listen.stop().catch(() => null);
  }

  async function startReading() {
    runRef.current++;
    setStage('starting');
    setKaraoke({ partial: '', cursor: INITIAL_CURSOR });
    setFinalCount(0);
    await stopRecorder();
    startRecorder();
    try {
      listeningRef.current = true;
      await listen.start();
      setStage('listening');
    } catch {
      listeningRef.current = false;
      await stopRecorder();
      setStage('ready');
    }
  }

  async function stopReading() {
    setStage('thinking');
    const [transcript, prosody] = await Promise.all([stopListening(), stopRecorder()]);
    await finish(transcript ?? { text: '', words: [] }, prosody);
  }

  /** Score the reading, store it, and give Pip up to two seconds to share what it noticed. */
  async function finish(transcript: Transcript, prosody: ProsodyStats | null) {
    const run = ++runRef.current;
    setStage('thinking');
    setFinalCount(matchForward(norms, tokenize(transcript.text)));

    let request: Promise<void> = Promise.resolve();
    try {
      const alignment = alignWords(page.text, transcript);
      const metrics = computeMetrics(alignment);
      set({ read: { transcript, alignment, metrics }, baselineProsody: prosody, diagnosis: undefined });
      // A late answer still lands in the session for Pip's turn, unless a newer reading replaced this one.
      request = postJson<DiagnoseResponse>('/api/diagnose', { pageText: page.text, alignment, metrics })
        .then((d) => {
          if (runRef.current === run && isDiagnosis(d)) set({ diagnosis: d });
        })
        .catch(() => {});
    } catch {
      set({ baselineProsody: prosody, diagnosis: undefined });
    }

    await Promise.race([Promise.all([request, wait(MIN_THINK_MS)]), wait(MAX_THINK_MS)]);
    if (runRef.current === run) setStage('done');
  }

  function onMic() {
    if (shown === 'ready') void startReading();
    else if (shown === 'listening') void stopReading();
  }

  const fillWithDemo = useEffectEvent(async () => {
    await stopListening();
    const prosody = await stopRecorder();
    await finish(DEMO_PAGE1_TRANSCRIPT, prosody);
  });
  const skipRead = useEffectEvent(() => advance());

  useEffect(() => {
    const offFill = registerDebugAction('Fill Read with demo transcript', () => void fillWithDemo());
    const offSkip = registerDebugAction('Skip Read', () => skipRead());
    return () => {
      offFill();
      offSkip();
    };
  }, [registerDebugAction]);

  // Leaving the screen mid-reading closes the mic and the pitch recorder.
  useEffect(
    () => () => {
      runRef.current++;
      if (listeningRef.current) {
        listeningRef.current = false;
        listenRef.current.stop().catch(() => {});
      }
      void stopRecorder();
    },
    // Unmount only. stopRecorder uses only refs and the stable recorder.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  );

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-[1120px] flex-col items-center px-5 pt-10 pb-6 sm:px-8 md:pt-14">
      <div className="flex w-full flex-1 flex-col items-center justify-center gap-10">
        <div className="relative w-full">
          <StoryBook
            page={page}
            words={words}
            readCount={readCount}
            currentIndex={currentIndex}
            underlined={underlined}
            settled={shown === 'done'}
          />
          <motion.div
            initial={{ opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.35, type: 'spring', stiffness: 180, damping: 16 }}
            className="pointer-events-none absolute -right-3 -bottom-14 sm:-right-6 lg:-right-16"
          >
            <Owl state={OWL_FOR_STAGE[shown]} size={136} />
          </motion.div>
        </div>

        <div className="flex min-h-[176px] w-full items-start justify-center">
          <AnimatePresence mode="wait" initial={false}>
            {shown === 'done' ? (
              <motion.div
                key="noticed"
                initial={{ opacity: 0, y: 16 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0 }}
                transition={{ type: 'spring', stiffness: 220, damping: 24 }}
                className="flex w-full justify-center md:justify-end"
              >
                <NoticedCard diagnosis={diagnosis} onNext={advance} />
              </motion.div>
            ) : shown === 'thinking' ? (
              <motion.div key="thinking" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="pt-12">
                <ThinkingNote />
              </motion.div>
            ) : (
              <motion.div key="mic" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
                <MicButton
                  state={shown === 'listening' ? 'listening' : shown === 'starting' ? 'disabled' : 'idle'}
                  onClick={onMic}
                  label={
                    shown === 'listening' ? 'Pip is listening. Tap when you finish.'
                    : shown === 'starting' ? 'Getting ready'
                    : micTrouble ? 'Tap to try again'
                    : 'Tap, then read to Pip'
                  }
                />
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>

      <StoryCredit book={book} className="mt-6 max-w-2xl text-center" />
    </main>
  );
}

function ThinkingNote() {
  return (
    <p className="flex items-baseline gap-1 font-display text-2xl text-ink-soft" aria-live="polite">
      Pip is thinking
      <span aria-hidden className="inline-flex gap-1">
        {[0, 1, 2].map((i) => (
          <motion.span
            key={i}
            className="inline-block size-1.5 rounded-full bg-ink-soft"
            animate={{ opacity: [0.25, 1, 0.25] }}
            transition={{ duration: 1, repeat: Infinity, delay: i * 0.2 }}
          />
        ))}
      </span>
    </p>
  );
}
