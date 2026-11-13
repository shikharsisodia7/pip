'use client';
// Parent and teacher report: what happened in this session, in plain terms.
// Every section is optional. A section whose data was not measured is hidden,
// and sample data is always labeled as sample data.

import clsx from 'clsx';
import { useRouter } from 'next/navigation';
import { useEffect, useMemo, useState, useSyncExternalStore } from 'react';
import Owl from '@/components/pip/Owl';
import { EvalFooter } from '@/components/report/EvalFooter';
import { NextSessionTile, TrustTile, practiceWords } from '@/components/report/NextSteps';
import { expressionView, mistakesView, patternsView, probeView, readingView, topPattern } from '@/components/report/derive';
import { SampleBadge } from '@/components/report/parts';
import { buildSampleReport, isSample } from '@/components/report/sample';
import { ExpressionTile, MistakesTile, PatternsTile, ProbeBand, ReadingTile } from '@/components/report/tiles';
import { BigButton } from '@/components/ui/BigButton';
import { Card } from '@/components/ui/Card';
import { postJson } from '@/lib/api';
import { isMock } from '@/lib/mock';
import { useSession } from '@/lib/session';
import type { PracticeBook } from '@/lib/types';

const noSubscribe = () => () => {};
/** Mock mode replays fixture transcripts, so its numbers are sample data too. */
const useMockMode = () => useSyncExternalStore(noSubscribe, isMock, () => false);

function BookIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" className="h-6 w-6" aria-hidden>
      <path d="M12 6.5C10.2 5 7.6 4.5 4 4.5v13c3.6 0 6.2.5 8 2 1.8-1.5 4.4-2 8-2v-13c-3.6 0-6.2.5-8 2z" />
      <path d="M12 6.5v13" />
    </svg>
  );
}

export default function Report() {
  const book = useSession((s) => s.book);
  const readPageIndex = useSession((s) => s.readPageIndex);
  const pipPageIndex = useSession((s) => s.pipPageIndex);
  const read = useSession((s) => s.read);
  const diagnosis = useSession((s) => s.diagnosis);
  const pipPlan = useSession((s) => s.pipPlan);
  const catches = useSession((s) => s.catches);
  const expression = useSession((s) => s.expression);
  const probePre = useSession((s) => s.probePre);
  const probePost = useSession((s) => s.probePost);
  const set = useSession((s) => s.set);
  const reset = useSession((s) => s.reset);
  const registerDebugAction = useSession((s) => s.registerDebugAction);
  const router = useRouter();
  const mock = useMockMode();
  const [bookStatus, setBookStatus] = useState<'idle' | 'loading' | 'error'>('idle');

  useEffect(
    () =>
      registerDebugAction('Fill report with demo data', () => {
        const s = useSession.getState();
        s.set(buildSampleReport(s.book, s.readPageIndex, s.pipPageIndex));
      }),
    [registerDebugAction],
  );

  const views = useMemo(() => {
    const mistakes = mistakesView(pipPlan, catches);
    return {
      reading: readingView(read?.metrics),
      mistakes,
      patterns: patternsView(diagnosis, mistakes),
      expression: expressionView(expression),
      probe: probeView(probePre, probePost),
      top: topPattern(diagnosis, mistakes),
    };
  }, [read, diagnosis, pipPlan, catches, expression, probePre, probePost]);

  const sample = mock || [read, diagnosis, pipPlan, catches, expression, probePre, probePost].some(isSample);
  const today = useMemo(
    () => new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' }),
    [],
  );
  const emotionLine = book.pages[pipPageIndex]?.emotionLine?.text;

  async function openPracticeBook() {
    if (!views.top || bookStatus === 'loading') return;
    setBookStatus('loading');
    try {
      const practiceBook = await postJson<PracticeBook>('/api/practice-book', { pattern: views.top });
      set({ practiceBook });
      router.push('/practice');
    } catch {
      setBookStatus('error');
    }
  }

  const tiles = [
    views.reading && <ReadingTile key="reading" view={views.reading} pageNumber={readPageIndex + 1} />,
    views.patterns && <PatternsTile key="patterns" view={views.patterns} />,
    views.mistakes && <MistakesTile key="mistakes" view={views.mistakes} />,
    views.expression && (
      <ExpressionTile key="expression" view={views.expression} line={emotionLine} pageNumber={readPageIndex + 1} />
    ),
  ].filter(Boolean);
  const hasContent = tiles.length > 0 || views.probe !== null;

  return (
    <main className="mx-auto w-full max-w-6xl px-4 py-6 sm:px-8 sm:py-8">
      <header className="flex flex-col gap-6 md:flex-row md:items-center md:justify-between">
        <div className="flex items-center gap-4 sm:gap-5">
          <Owl state="idle" size={84} className="shrink-0" />
          <div>
            <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
              <h1 className="font-display text-4xl font-semibold tracking-tight sm:text-5xl">What Pip learned today</h1>
              {sample && hasContent && <SampleBadge />}
            </div>
            <p className="mt-2 text-lg text-ink-soft">
              From reading <span className="font-semibold text-ink">“{book.title}”</span> on {today}
            </p>
          </div>
        </div>
        {views.top && (
          <div className="flex flex-col items-start gap-2 md:items-end">
            <BigButton size="md" onClick={openPracticeBook} disabled={bookStatus === 'loading'} className="whitespace-nowrap">
              <BookIcon />
              {bookStatus === 'loading' ? 'Making the book…' : "Pip's Practice Book"}
            </BigButton>
            {bookStatus === 'error' && (
              <p className="text-sm text-ink-soft" role="status">The practice book did not load. Try again.</p>
            )}
          </div>
        )}
      </header>

      {hasContent ? (
        <div className="mt-6 overflow-hidden rounded-card border border-line bg-line shadow-soft">
          <div className="grid gap-px md:grid-cols-2">
            {views.probe && <ProbeBand view={views.probe} className="md:col-span-2" />}
            {tiles.map((tile, i) => (
              <div key={i} className={clsx('grid', tiles.length % 2 === 1 && i === tiles.length - 1 && 'md:col-span-2')}>
                {tile}
              </div>
            ))}
          </div>
        </div>
      ) : (
        <Card className="mt-6 p-10 text-center">
          <p className="font-display text-2xl font-semibold">Nothing to show yet</p>
          <p className="mt-2 text-lg text-ink-soft">This report fills in after a reading session with Pip.</p>
        </Card>
      )}

      <div className="mt-6 overflow-hidden rounded-card border border-line bg-line shadow-soft">
        <div className="grid gap-px md:grid-cols-2">
          {hasContent && views.top && (
            <NextSessionTile pattern={views.top} words={practiceWords(views.top.id, [probePre, probePost])} />
          )}
          <TrustTile className={clsx(!(hasContent && views.top) && 'md:col-span-2')} />
        </div>
      </div>

      <footer className="mt-8 flex flex-col gap-6 sm:flex-row sm:items-end sm:justify-between">
        <EvalFooter />
        <BigButton variant="quiet" size="md" onClick={reset} className="self-start sm:ml-auto sm:self-auto">
          Start over
        </BigButton>
      </footer>
    </main>
  );
}
