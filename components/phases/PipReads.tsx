'use client';

// "Your turn to be the teacher!" Pip reads the next page flat with a planted
// mistake on a sound the child found tricky, asks "Did I get that right?", and
// only then opens the mic. A catch by voice or by tapping the word celebrates,
// plays Pip's reaction and re-reads the sentence correctly, so the right model
// is always the last thing the child hears.

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import clsx from 'clsx';
import { AnimatePresence, motion } from 'framer-motion';
import { BigButton, MicButton, StoryCredit } from '@/components/ui';
import Owl, { type OwlState } from '@/components/pip/Owl';
import SpeechBubble from '@/components/pip/SpeechBubble';
import Celebration from '@/components/pip/Celebration';
import { useSession } from '@/lib/session';
import { postJson } from '@/lib/api';
import { tokenizeDisplay } from '@/lib/text';
import { useListen } from '@/lib/scribe/useListen';
import { injectMockTranscript, transcriptFromText } from '@/lib/scribe/mock';
import { expressive, flat, prefetch, speak } from '@/lib/pip/tts';
import { lineRequest, lineText, type PipLineId } from '@/lib/pip/lines';
import { isSpeaking, playAndWait, stopSpeaking } from '@/lib/pip/player';
import { detectCatch, isBareObjection } from '@/lib/pip/catch';
import { misreadDisplay } from '@/lib/pip/reads-plan';
import type { CatchResult, PipPlan, PipSentence, PlantedMistake, Transcript } from '@/lib/types';

const LISTEN_MS = 6000;
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

export default function PipReads() {
  const book = useSession((s) => s.book);
  const pipPageIndex = useSession((s) => s.pipPageIndex);
  const demoPath = useSession((s) => s.demoPath);
  const { advance, set, setDebug, registerDebugAction } = useSession.getState();
  const page = book.pages[pipPageIndex] ?? book.pages[book.pages.length - 1];
  const tokens = useMemo(() => tokenizeDisplay(page.text), [page.text]);

  const listen = useListen();
  const listenRef = useRef(listen);
  listenRef.current = listen;

  const [plan, setPlan] = useState<PipPlan | null>(null);
  const [current, setCurrent] = useState(-1);
  const [lit, setLit] = useState<Set<number>>(new Set());
  const [fixed, setFixed] = useState<Set<number>>(new Set());
  const [bubble, setBubble] = useState('');
  const [owl, setOwl] = useState<OwlState>('thinking');
  const [listening, setListening] = useState(false);
  const [finished, setFinished] = useState(false);
  const [confetti, setConfetti] = useState(0);

  const alive = useRef(true);
  const runId = useRef(0);
  const planRef = useRef<PipPlan | null>(null);
  const currentRef = useRef(-1);
  const fixedRef = useRef<Set<number>>(new Set());
  const catches = useRef<CatchResult[]>([]);
  const tapCaught = useRef<number | null>(null);
  const stopRequested = useRef(false);
  const skipRequested = useRef(false);

  const mistakeAt = (i: number) => plan?.mistakes.find((m) => m.wordIndex === i);
  const sentenceOf = (i: number) => plan?.sentences.findIndex((s) => i >= s.wordStart && i < s.wordEnd) ?? -1;

  const say = useCallback(async (id: PipLineId) => {
    setBubble(lineText(id));
    setOwl('speaking');
    const resp = await speak(lineRequest(id));
    if (alive.current) await playAndWait(resp);
  }, []);

  const readSentence = useCallback(async (s: PipSentence, spoken: boolean) => {
    setLit(new Set());
    setBubble('');
    setOwl('speaking');
    const resp = await speak(flat(spoken ? s.spokenText : s.text));
    if (!alive.current) return;
    await playAndWait(resp, {
      onWord: (i) => {
        const idx = s.wordStart + i;
        if (alive.current && idx < s.wordEnd) setLit((prev) => new Set(prev).add(idx));
      },
    });
    if (alive.current) setOwl('idle');
  }, []);

  const markFixed = (i: number) => {
    fixedRef.current = new Set(fixedRef.current).add(i);
    setFixed(fixedRef.current);
  };

  const record = (r: CatchResult) => {
    catches.current = [...catches.current, r];
    set({ catches: catches.current });
  };

  const caught = useCallback(async (m: PlantedMistake, s: PipSentence, via: 'voice' | 'tap') => {
    tapCaught.current = null;
    setConfetti((c) => c + 1);
    record({ wordIndex: m.wordIndex, caught: true, via });
    markFixed(m.wordIndex);
    setOwl('celebrating');
    setBubble(m.reaction);
    const resp = await speak(expressive(m.reaction));
    if (alive.current) await playAndWait(resp);
    if (alive.current) await readSentence(s, false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [readSentence]);

  const listenFor = useCallback(async (m: PlantedMistake): Promise<Transcript> => {
    if (isSpeaking()) return { text: '', words: [] }; // the mic never opens while Pip talks
    stopRequested.current = false;
    setOwl('listening');
    setBubble('');
    await listenRef.current.start();
    setListening(true);
    const started = Date.now();
    while (alive.current && !stopRequested.current && Date.now() - started < LISTEN_MS) {
      // Stop early as soon as the correct word is heard, so the catch feels instant.
      if (detectCatch(transcriptFromText(listenRef.current.partialText), m)) break;
      await wait(100);
    }
    const t = await listenRef.current.stop();
    setListening(false);
    setOwl('idle');
    return t;
  }, []);

  const teach = useCallback(async (m: PlantedMistake, s: PipSentence) => {
    let askedWhich = false;
    let tries = 0;
    while (alive.current && !skipRequested.current) {
      if (tapCaught.current === m.wordIndex) return caught(m, s, 'tap');
      await say(askedWhich ? 'whichWord' : 'didIGetItRight');
      if (tapCaught.current === m.wordIndex) return caught(m, s, 'tap');
      const t = await listenFor(m);
      if (tapCaught.current === m.wordIndex) return caught(m, s, 'tap');
      if (skipRequested.current) return;
      const hit = detectCatch(t, m);
      setDebug('pipReads.lastTranscript', t.text);
      setDebug('pipReads.match', hit ? 'caught' : 'not caught');
      if (hit) return caught(m, s, 'voice');
      if (!askedWhich && isBareObjection(t, m)) {
        askedWhich = true;
        continue;
      }
      tries += 1;
      if (tries >= 2) break;
    }
    if (!alive.current || skipRequested.current) return;
    // Not caught: Pip notices and fixes it himself, then models it.
    setOwl('confused');
    await say('mixedOneUp');
    markFixed(m.wordIndex);
    record({ wordIndex: m.wordIndex, caught: false, via: 'missed' });
    await readSentence(s, false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [caught, listenFor, readSentence, say, setDebug]);

  // Main sequence.
  useEffect(() => {
    alive.current = true;
    // React may mount this effect twice in development; only the latest run continues.
    const myRun = ++runId.current;
    const live = () => alive.current && runId.current === myRun;
    (async () => {
      const patterns = useSession.getState().diagnosis?.patterns ?? [];
      let p: PipPlan;
      try {
        p = await postJson<PipPlan>('/api/pip-mistakes', {
          pageIndex: page.index,
          pageText: page.text,
          patterns,
          count: demoPath === '2min' ? 1 : 2,
          emotionLineText: page.emotionLine?.text,
        });
      } catch {
        p = { pageIndex: page.index, sentences: [], mistakes: [] };
      }
      if (!live()) return;
      planRef.current = p;
      setPlan(p);
      set({ pipPlan: p, catches: [] });
      setDebug('pipReads.plan', p.mistakes.map((m) => `${m.correct} -> ${m.misread}`).join(', '));

      void prefetch([
        ...p.sentences.map((s) => flat(s.spokenText)),
        ...p.mistakes.flatMap((m) => [flat(p.sentences[m.sentenceIndex].text), expressive(m.reaction)]),
        ...(['didIGetItRight', 'whichWord', 'mixedOneUp'] as PipLineId[]).map(lineRequest),
      ]);

      const order = demoPath === '2min' && p.mistakes[0] ? [p.mistakes[0].sentenceIndex] : p.sentences.map((s) => s.index);
      for (const si of order) {
        if (!live()) return;
        currentRef.current = si;
        setCurrent(si);
        skipRequested.current = false;
        const s = p.sentences[si];
        await readSentence(s, true);
        if (!live()) return;
        const m = p.mistakes.find((x) => x.sentenceIndex === si);
        if (m && !fixedRef.current.has(m.wordIndex)) await teach(m, s);
        else await wait(450);
      }
      if (!live()) return;
      currentRef.current = -1;
      setCurrent(-1);
      setLit(new Set());
      setBubble('');
      setOwl('celebrating');
      setFinished(true);
    })();
    return () => {
      alive.current = false;
      stopSpeaking();
      if (listenRef.current.status === 'listening') void listenRef.current.stop();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Debug panel hooks.
  useEffect(() => {
    const firstOpen = () =>
      planRef.current?.mistakes.find((m) => !fixedRef.current.has(m.wordIndex) && currentRef.current >= m.sentenceIndex);
    const offs = [
      registerDebugAction('Force catch', () => {
        const m = firstOpen();
        if (m) { tapCaught.current = m.wordIndex; stopRequested.current = true; }
      }),
      registerDebugAction('Skip sentence', () => {
        skipRequested.current = true;
        stopRequested.current = true;
        stopSpeaking();
      }),
      registerDebugAction('Replay sentence', () => {
        const p = planRef.current;
        if (p && p.sentences[currentRef.current]) void readSentence(p.sentences[currentRef.current], fixedRef.current.size === 0);
      }),
      registerDebugAction('Queue catch transcript', () => {
        const m = planRef.current?.mistakes[0];
        if (m) injectMockTranscript(`no it says ${m.correct}`);
      }),
    ];
    return () => offs.forEach((off) => off());
  }, [readSentence, registerDebugAction]);

  const tapWord = (i: number) => {
    const m = mistakeAt(i);
    if (!m || fixed.has(i) || current < m.sentenceIndex) return;
    tapCaught.current = i;
    stopRequested.current = true;
  };

  return (
    <main className="mx-auto flex min-h-screen max-w-6xl flex-col gap-6 px-6 py-8">
      <Celebration fire={confetti} />
      <h1 className="font-display text-4xl text-ink md:text-5xl">Your turn to be the teacher!</h1>

      <section className="grid items-stretch gap-6 md:grid-cols-[300px_1fr]">
        <div className="relative flex flex-col items-center justify-end rounded-[24px] p-6 shadow-soft" style={{ background: page.scene.bg }}>
          <span className="absolute left-6 top-5 text-5xl opacity-80" aria-hidden>{page.scene.emoji}</span>
          <AnimatePresence>
            {bubble && (
              <motion.div key={bubble} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} className="mb-2 w-full">
                <SpeechBubble tail="bottom"><span className="font-display text-xl text-ink">{bubble}</span></SpeechBubble>
              </motion.div>
            )}
          </AnimatePresence>
          <Owl state={owl} size={200} />
        </div>

        <div className="flex flex-col gap-4 rounded-[24px] bg-paper p-8 shadow-soft">
          <p className="story-text flex flex-wrap gap-x-2 gap-y-1">
            {tokens.map((t, i) => {
              const m = mistakeAt(i);
              const si = sentenceOf(i);
              const showMisread = !!m && !fixed.has(i) && current >= m.sentenceIndex;
              const dim = current >= 0 && si !== current;
              return (
                <motion.button
                  key={i}
                  type="button"
                  onClick={() => tapWord(i)}
                  animate={fixed.has(i) ? { rotateX: [0, 360] } : {}}
                  transition={{ duration: 0.5 }}
                  className={clsx(
                    'rounded-xl px-1.5 text-left transition-colors duration-150',
                    fixed.has(i) ? 'bg-[#c9f2e1]' : lit.has(i) ? 'bg-sun-soft' : 'bg-transparent',
                    showMisread && 'underline decoration-[#ff9f43] decoration-4 underline-offset-8',
                    dim && 'opacity-50',
                    m && 'cursor-pointer',
                  )}
                >
                  {showMisread ? misreadDisplay(t.display, m!.misread) : t.display}
                </motion.button>
              );
            })}
          </p>
          <StoryCredit book={book} className="mt-auto" />
        </div>
      </section>

      <div className="flex flex-wrap items-center gap-6">
        {listening ? (
          <>
            <MicButton state="listening" label="Tap when you finish" onClick={() => { stopRequested.current = true; }} />
            <p className="font-display text-2xl text-ink">
              {listen.partialText ? `“${listen.partialText}”` : 'Pip is listening. Did he get it right?'}
            </p>
          </>
        ) : finished ? (
          <p className="font-display text-2xl text-ink">You&apos;re a great teacher!</p>
        ) : (
          <p className="text-xl text-ink-soft">Listen closely. You can tap a word Pip got wrong.</p>
        )}
        <div className="ml-auto">
          {finished ? <BigButton onClick={advance}>Next</BigButton> : <BigButton variant="quiet" size="md" onClick={advance}>Skip</BigButton>}
        </div>
      </div>
    </main>
  );
}
