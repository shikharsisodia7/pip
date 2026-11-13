'use client';

// The expression moment. Pip reads an emotional line flat and asks how it should
// sound. The reader performs it while their voice draws a live pitch line. If
// they are clearly more expressive than their own reading baseline, Pip learns
// it and performs the line with feeling (eleven_v3 with audio tags).

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import clsx from 'clsx';
import { AnimatePresence, motion } from 'framer-motion';
import { BigButton, Card, Meter, MicButton, StoryCredit } from '@/components/ui';
import Owl, { type OwlState } from '@/components/pip/Owl';
import SpeechBubble from '@/components/pip/SpeechBubble';
import Celebration from '@/components/pip/Celebration';
import PitchContour from '@/components/expression/PitchContour';
import { useSession } from '@/lib/session';
import { postJson } from '@/lib/api';
import { tokenizeDisplay } from '@/lib/text';
import { expressive, flat, prefetch, speak } from '@/lib/pip/tts';
import { lineRequest, lineText, ALL_LINE_REQUESTS, type PipLineId } from '@/lib/pip/lines';
import { isSpeaking, play, playAndWait, stopSpeaking } from '@/lib/pip/player';
import {
  createProsodyRecorder, expressionScore, getThreshold, nudgeThreshold, emptyStats,
  type ProsodyRecorder,
} from '@/lib/prosody';
import type { Emotion, EmotionLine, ExpressionResult, ProsodyFrame, ProsodyStats } from '@/lib/types';

type Stage =
  | 'loading' | 'pipFlat' | 'asking' | 'ready' | 'recording' | 'scoring'
  | 'retry' | 'learning' | 'learned' | 'practicing';

const EMOTION_HINT: Record<Emotion, { icon: string; word: string }> = {
  scared: { icon: '😨', word: 'scared' },
  excited: { icon: '🤩', word: 'excited' },
  sad: { icon: '😢', word: 'sad' },
  whispering: { icon: '🤫', word: 'whispering' },
  shouting: { icon: '📣', word: 'shouting' },
  happy: { icon: '😊', word: 'happy' },
  angry: { icon: '😠', word: 'angry' },
};

const MAX_RECORD_MS = 7000;
const MAX_FAILED_TRIES = 2;

function findLine(pages: { emotionLine?: EmotionLine; text: string }[], preferred: number) {
  const page = pages[preferred]?.emotionLine ? pages[preferred] : pages.find((p) => p.emotionLine);
  return page ? { line: page.emotionLine as EmotionLine, context: page.text } : null;
}

export default function Expression() {
  const book = useSession((s) => s.book);
  const pipPageIndex = useSession((s) => s.pipPageIndex);
  const baseline = useSession((s) => s.baselineProsody ?? null);
  const { advance, set, setDebug, registerDebugAction } = useSession.getState();

  const found = useMemo(() => findLine(book.pages, pipPageIndex), [book.pages, pipPageIndex]);
  const line: EmotionLine = found?.line ?? { text: 'Oh no! What was that?', emotion: 'scared' };
  const words = useMemo(() => tokenizeDisplay(line.text), [line.text]);
  const hint = EMOTION_HINT[line.emotion] ?? EMOTION_HINT.excited;

  const [stage, setStage] = useState<Stage>('loading');
  const [lit, setLit] = useState(-1);
  const [bubble, setBubble] = useState<string>('');
  const [frames, setFrames] = useState<ProsodyFrame[]>([]);
  const [attempts, setAttempts] = useState(0);
  const [score, setScore] = useState<number | null>(null);
  const [confetti, setConfetti] = useState(0);
  const [micError, setMicError] = useState<string | null>(null);
  const [micStarting, setMicStarting] = useState(false);
  const [tagged, setTagged] = useState<{ taggedText: string; tags: string[] } | null>(null);

  const alive = useRef(true);
  const recorder = useRef<ProsodyRecorder | null>(null);
  const framesRef = useRef<ProsodyFrame[]>([]);
  const rafRef = useRef(0);
  const stopTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastStats = useRef<ProsodyStats | null>(null);
  const attemptsRef = useRef(0);
  const taggedRef = useRef<{ taggedText: string; tags: string[] } | null>(null);

  const say = useCallback(async (id: PipLineId) => {
    setBubble(lineText(id));
    const resp = await speak(lineRequest(id));
    if (alive.current) await playAndWait(resp);
  }, []);

  const readFlat = useCallback(async () => {
    setLit(-1);
    setBubble(line.text);
    const resp = await speak(flat(line.text));
    if (!alive.current) return;
    await playAndWait(resp, { onWord: (i) => alive.current && setLit(i) });
  }, [line.text]);

  const getTagged = useCallback(async () => {
    if (taggedRef.current) return taggedRef.current;
    let t: { taggedText: string; tags: string[] };
    try {
      t = await postJson<{ taggedText: string; tags: string[] }>('/api/expression-tags', {
        line, context: found?.context ?? '',
      });
    } catch {
      t = { taggedText: `[excited] ${line.text}`, tags: ['excited'] };
    }
    taggedRef.current = t;
    setTagged(t);
    return t;
  }, [line, found?.context]);

  const readExpressive = useCallback(async () => {
    const t = await getTagged();
    setLit(-1);
    setBubble(line.text);
    const resp = await speak(expressive(t.taggedText));
    if (alive.current) await playAndWait(resp);
  }, [getTagged, line.text]);

  const store = useCallback((attempt: ProsodyStats, s: number, passed: boolean) => {
    const result: ExpressionResult = {
      baseline, attempt, score: Math.round(s * 100) / 100, passed,
      attempts: attemptsRef.current, tags: taggedRef.current?.tags ?? [],
    };
    set({ expression: result });
    setDebug('expression.result', result);
  }, [baseline, set, setDebug]);

  const learn = useCallback(async (attempt: ProsodyStats, s: number) => {
    store(attempt, s, true);
    setStage('learning');
    setConfetti((c) => c + 1);
    await say('likeThis');
    if (!alive.current) return;
    await readExpressive();
    if (alive.current) setStage('learned');
  }, [readExpressive, say, store]);

  const notYet = useCallback(async (attempt: ProsodyStats, s: number) => {
    if (attemptsRef.current >= MAX_FAILED_TRIES) {
      store(attempt, s, false);
      setStage('practicing');
      await say('keepPracticing');
      return;
    }
    setStage('retry');
    await say('showMeAgain');
    if (alive.current) setStage('ready');
  }, [say, store]);

  // Intro sequence: prefetch, read flat, ask how it should sound.
  useEffect(() => {
    alive.current = true;
    (async () => {
      const t = await getTagged();
      void prefetch([flat(line.text), expressive(t.taggedText), ...ALL_LINE_REQUESTS]);
      await speak(flat(line.text)).catch(() => undefined);
      if (!alive.current) return;
      setStage('pipFlat');
      await readFlat();
      if (!alive.current) return;
      setStage('asking');
      await say('howShouldItSound');
      if (alive.current) setStage('ready');
    })();
    return () => {
      alive.current = false;
      stopSpeaking();
      cancelAnimationFrame(rafRef.current);
      if (stopTimer.current) clearTimeout(stopTimer.current);
      void recorder.current?.stop();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const stopRecording = useCallback(async () => {
    const rec = recorder.current;
    if (!rec) return;
    recorder.current = null;
    if (stopTimer.current) clearTimeout(stopTimer.current);
    setStage('scoring');
    const stats = await rec.stop();
    cancelAnimationFrame(rafRef.current);
    setFrames([...framesRef.current]);
    lastStats.current = stats;
    attemptsRef.current += 1;
    setAttempts(attemptsRef.current);
    const result = expressionScore(stats, baseline);
    setScore(result.score);
    setDebug('expression.attempt', stats);
    setDebug('expression.score', { ...result, threshold: getThreshold() });
    if (!alive.current) return;
    if (result.passed) await learn(stats, result.score);
    else await notYet(stats, result.score);
  }, [baseline, learn, notYet, setDebug]);

  const startRecording = useCallback(async () => {
    if (isSpeaking() || recorder.current) return; // the mic never opens while Pip talks
    setMicError(null);
    framesRef.current = [];
    setFrames([]);
    setBubble('');
    const rec = createProsodyRecorder();
    rec.onFrame((f) => {
      framesRef.current.push(f);
      if (!rafRef.current) {
        rafRef.current = requestAnimationFrame(() => {
          rafRef.current = 0;
          if (alive.current) setFrames([...framesRef.current]);
        });
      }
    });
    recorder.current = rec;
    setMicStarting(true);
    try {
      await rec.start();
      setMicStarting(false);
    } catch {
      setMicStarting(false);
      recorder.current = null;
      setMicError('Pip cannot hear the microphone. Check the mic permission and try again.');
      setStage('ready');
      return;
    }
    setStage('recording');
    stopTimer.current = setTimeout(() => void stopRecording(), MAX_RECORD_MS);
  }, [stopRecording]);

  // Debug panel hooks.
  const forcePass = useCallback(() => {
    stopSpeaking();
    const attempt = lastStats.current ?? { ...emptyStats(), pitchSdSemitones: 4, pitchRangeSemitones: 12, loudnessSdDb: 5, voicedFrames: 80 };
    attemptsRef.current = Math.max(1, attemptsRef.current);
    const s = Math.max(getThreshold(), score ?? 0);
    setScore(s);
    void learn(attempt, s);
  }, [learn, score]);

  const forceFail = useCallback(() => {
    stopSpeaking();
    attemptsRef.current += 1;
    setAttempts(attemptsRef.current);
    void notYet(lastStats.current ?? emptyStats(), 0);
  }, [notYet]);

  useEffect(() => {
    const showThreshold = () => setDebug('expression.threshold', getThreshold());
    showThreshold();
    setDebug('expression.baseline', baseline);
    const offs = [
      registerDebugAction('Force pass', forcePass),
      registerDebugAction('Force fail', forceFail),
      registerDebugAction('Replay flat', () => void readFlat()),
      registerDebugAction('Replay expressive', () => void readExpressive()),
      registerDebugAction('Threshold +0.05', () => { nudgeThreshold(0.05); showThreshold(); }),
      registerDebugAction('Threshold -0.05', () => { nudgeThreshold(-0.05); showThreshold(); }),
    ];
    return () => offs.forEach((off) => off());
  }, [baseline, forceFail, forcePass, readExpressive, readFlat, registerDebugAction, setDebug]);

  const pipBusy = ['loading', 'pipFlat', 'asking', 'retry', 'learning', 'scoring'].includes(stage);
  const owlState: OwlState =
    stage === 'learning' || stage === 'learned' ? (stage === 'learning' ? 'speaking' : 'celebrating')
      : stage === 'retry' ? 'confused'
      : stage === 'recording' ? 'listening'
      : stage === 'scoring' || stage === 'loading' ? 'thinking'
      : pipBusy ? 'speaking' : 'idle';
  const done = stage === 'learned' || stage === 'practicing';
  const threshold = getThreshold();
  const meterValue = stage === 'learned' || stage === 'learning' ? 1 : score === null ? 0 : Math.min(0.95, score / (threshold * 1.15));

  const prompt =
    micStarting ? 'Waiting for the microphone...'
      : stage === 'ready' ? (attempts ? 'Try again! Make it sound really ' + hint.word + '.' : 'Your turn! Read it the way ' + (line.speaker ?? 'they') + ' would say it.')
      : stage === 'recording' ? 'Pip is listening to how it sounds...'
      : stage === 'practicing' ? 'Pip will keep practicing. Great teaching!'
      : '';

  return (
    <main className="mx-auto flex min-h-screen max-w-6xl flex-col gap-6 px-6 py-8">
      <Celebration fire={confetti} />
      <header className="flex items-center justify-between">
        <h1 className="font-display text-4xl text-ink md:text-5xl">How should it sound?</h1>
        <div className="flex items-center gap-2 rounded-full bg-paper px-4 py-2 text-lg text-ink-soft shadow-soft">
          <span className="text-2xl" aria-hidden>{hint.icon}</span>
          <span>Feeling: <b className="text-ink">{hint.word}</b></span>
        </div>
      </header>

      <section className="grid items-center gap-6 md:grid-cols-[auto_1fr]">
        <div className="relative mx-auto">
          <Owl state={owlState} size={230} />
          <AnimatePresence>
            {bubble && pipBusy && bubble !== line.text && (
              <motion.div
                key={bubble}
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0 }}
                className="absolute -top-4 left-[85%] z-10 w-64"
              >
                <SpeechBubble tail="left"><span className="font-display text-xl text-ink">{bubble}</span></SpeechBubble>
              </motion.div>
            )}
          </AnimatePresence>
        </div>

        <Card className="relative p-8 md:p-10">
          {line.speaker && <p className="mb-2 font-display text-xl text-ink-soft">{line.speaker} says:</p>}
          <p className="font-display text-5xl leading-tight text-ink md:text-6xl">
            {words.map((w, i) => (
              <span
                key={i}
                className={clsx(
                  'inline-block rounded-2xl px-1 transition-colors duration-150',
                  stage === 'pipFlat' && i <= lit && 'bg-sun-soft',
                  stage === 'pipFlat' && i === lit && 'bg-sun',
                )}
              >
                {w.display}&nbsp;
              </span>
            ))}
          </p>
          <AnimatePresence>
            {(stage === 'learned' || stage === 'learning') && (
              <motion.div
                initial={{ scale: 0.6, opacity: 0, rotate: -6 }}
                animate={{ scale: 1, opacity: 1, rotate: -4 }}
                className="absolute -right-3 -top-5 rounded-full bg-sun px-5 py-2 font-display text-2xl text-ink shadow-lift"
              >
                Pip learned it!
              </motion.div>
            )}
          </AnimatePresence>
        </Card>
      </section>

      <Card className="p-4 md:p-6">
        <PitchContour frames={frames} active={stage === 'recording'} />
        <div className="mt-4 flex flex-col items-center gap-4 md:flex-row md:justify-between">
          <div className="w-full max-w-md">
            <Meter value={meterValue} tone={stage === 'learned' || stage === 'learning' ? 'sun' : 'accent'} label="Feeling" height={22} />
          </div>
          <p className="min-h-8 text-center font-display text-2xl text-ink">{prompt}</p>
        </div>
      </Card>

      {micError && <p className="text-center text-xl text-ink-soft">{micError}</p>}

      <div className="flex flex-wrap items-center justify-center gap-6">
        {!done && (
          <MicButton
            state={stage === 'recording' ? 'listening' : stage === 'ready' ? 'idle' : 'disabled'}
            label={stage === 'recording' ? 'Tap when you finish' : stage === 'ready' ? 'Tap and say it with feeling' : 'Pip is talking'}
            onClick={() => (stage === 'recording' ? void stopRecording() : void startRecording())}
          />
        )}
        {done && (
          <>
            {stage === 'learned' && (
              <BigButton variant="secondary" onClick={() => void readExpressive()}>Hear Pip again</BigButton>
            )}
            <BigButton onClick={advance}>Next</BigButton>
          </>
        )}
        {!done && (
          <BigButton variant="quiet" size="md" onClick={advance}>Skip</BigButton>
        )}
      </div>

      <StoryCredit book={book} className="mt-auto" />
      {tagged && <span className="sr-only">Pip will say it with: {tagged.tags.join(', ')}</span>}
    </main>
  );
}
