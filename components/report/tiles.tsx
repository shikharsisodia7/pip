'use client';
// The report's sections. Each one renders only what was measured; the parent
// decides whether a section appears at all (see derive.ts).

import clsx from 'clsx';
import { Meter } from '@/components/ui/Meter';
import type { CatchOutcome, ExpressionView, MistakesView, PatternsView, ProbeSide, ProbeView, ReadingView } from './derive';
import { BookWord, CheckIcon, Tile } from './parts';

const plural = (n: number, one: string, many: string) => (n === 1 ? one : many);

// Reading -----------------------------------------------------------------------

export function ReadingTile({ view, pageNumber, className }: { view: ReadingView; pageNumber: number; className?: string }) {
  const { wcpm, accuracyPct, wordsCorrect, wordsTotal, durationSec } = view;
  const basis = [
    wordsCorrect !== undefined ? `${wordsCorrect} of ${wordsTotal} words read correctly` : `${wordsTotal} words`,
    durationSec !== undefined ? `in ${durationSec} ${plural(durationSec, 'second', 'seconds')}` : '',
  ].filter(Boolean).join(' ');
  return (
    <Tile title="Reading" className={className}>
      <div className="mt-5 grid grid-cols-[auto_1fr] items-baseline gap-x-4 gap-y-3">
        {wcpm !== undefined && (
          <>
            <span className="font-display text-4xl font-semibold leading-none tabular-nums sm:text-5xl">{wcpm}</span>
            <span className="text-lg text-ink-soft">words correct per minute</span>
          </>
        )}
        {accuracyPct !== undefined && (
          <>
            <span className="font-display text-4xl font-semibold leading-none tabular-nums sm:text-5xl">{accuracyPct}%</span>
            <span className="text-lg text-ink-soft">accuracy, words read as printed</span>
          </>
        )}
      </div>
      <p className="mt-5 text-ink-soft">
        Words read right in one minute, how teachers track fluency.
      </p>
      <p className="mt-2 text-sm text-ink-soft">From page {pageNumber}: {basis}.</p>
    </Tile>
  );
}

// Patterns ----------------------------------------------------------------------

export function PatternsTile({ view, className }: { view: PatternsView; className?: string }) {
  return (
    <Tile title="Phonics patterns" className={className}>
      {view.needsPractice.length > 0 && (
        <div className="mt-5">
          <h3 className="font-semibold text-ink-soft">Needs practice</h3>
          <ul className="mt-2.5 space-y-2.5">
            {view.needsPractice.map((p) => (
              <li key={p.id} className="flex flex-wrap items-center gap-x-3 gap-y-1.5">
                <span className="font-display text-lg font-medium">{p.teacherLabel}</span>
                {p.words.map((w) => <BookWord key={w}>{w}</BookWord>)}
              </li>
            ))}
          </ul>
        </div>
      )}
      {view.practicedToday.length > 0 && (
        <div className="mt-6">
          <h3 className="font-semibold text-ink-soft">Practiced today</h3>
          <ul className="mt-2.5 flex flex-wrap gap-2">
            {view.practicedToday.map((p) => (
              <li key={p.id} className="rounded-full bg-accent-soft px-3.5 py-1.5 font-semibold text-accent-deep">
                {p.teacherLabel}
              </li>
            ))}
          </ul>
        </div>
      )}
    </Tile>
  );
}

// Mistakes caught -----------------------------------------------------------------

const OUTCOME: Record<CatchOutcome, string> = {
  voice: 'Caught out loud',
  tap: 'Caught with a tap',
  missed: 'Not caught this time',
};

export function MistakesTile({ view, className }: { view: MistakesView; className?: string }) {
  return (
    <Tile title="Mistakes caught" className={className}>
      <p className="mt-5 flex flex-wrap items-baseline gap-x-4 gap-y-1">
        <span className="font-display text-4xl font-semibold leading-none tabular-nums sm:text-5xl">
          {view.caught} of {view.total}
        </span>
        <span className="text-lg text-ink-soft">{plural(view.total, 'planted mistake', 'planted mistakes')}</span>
      </p>
      <p className="mt-3 text-ink-soft">
        Pip misread {plural(view.total, 'this word', 'these words')} on purpose, for your reader to catch.
      </p>
      <ul className="mt-3 divide-y divide-line">
        {view.rows.map((r) => (
          <li key={r.wordIndex} className="flex flex-wrap items-center gap-x-3 gap-y-1 py-2.5">
            <span className="sr-only">Pip said</span>
            <s className="font-story text-lg text-ink-soft decoration-accent/70 decoration-2">{r.misread}</s>
            <span className="sr-only">instead of</span>
            <BookWord>{r.correct}</BookWord>
            <span
              className={clsx(
                'ml-auto inline-flex items-center gap-1.5 text-sm font-semibold',
                r.outcome === 'missed' ? 'text-ink-soft' : 'text-accent-deep',
              )}
            >
              {r.outcome !== 'missed' && <CheckIcon />}
              {OUTCOME[r.outcome]}
            </span>
          </li>
        ))}
      </ul>
    </Tile>
  );
}

// Expression ----------------------------------------------------------------------

export function ExpressionTile({ view, line, pageNumber, className }: {
  view: ExpressionView; line?: string; pageNumber: number; className?: string;
}) {
  const { bars } = view;
  return (
    <Tile title="Expression" className={className}>
      {line && <p className="mt-4 font-story text-xl leading-snug">“{line}”</p>}
      {bars && (
        <>
          <div className="mt-5 space-y-4">
            <Meter value={bars.baseline / bars.scale} label="Usual reading voice" valueLabel="1.0×" tone="muted" height={14} />
            <Meter value={bars.attempt / bars.scale} label="Acting out the line" valueLabel={`${bars.attempt.toFixed(1)}×`} height={14} />
          </div>
          <p className="mt-4 text-ink-soft">
            Changes in pitch and volume, compared with reading page {pageNumber}.
          </p>
        </>
      )}
      <p className="mt-3 font-semibold">
        {view.passed ? 'Pip learned to read it with feeling.' : 'Pip is still practicing this line.'}
      </p>
    </Tile>
  );
}

// Before and after word checks -------------------------------------------------------

function WordChips({ side, label }: { side: ProbeSide; label: string }) {
  return (
    <>
      <span className="text-sm font-semibold text-ink-soft">{label}</span>
      <ul className="flex flex-wrap gap-2" aria-label={`${label}: ${side.correct} of ${side.total} read correctly`}>
        {side.items.map((item, i) => (
          <li
            key={`${item.word}-${i}`}
            className={clsx(
              'inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1 font-story text-base',
              item.correct ? 'bg-sun-soft text-ink' : 'bg-cream text-ink-soft ring-1 ring-line ring-inset',
            )}
          >
            {item.correct && <CheckIcon className="h-3.5 w-3.5 text-bark" />}
            {item.word}
            <span className="sr-only">{item.correct ? ', read correctly' : ', not yet'}</span>
          </li>
        ))}
      </ul>
    </>
  );
}

export function ProbeBand({ view, className }: { view: ProbeView; className?: string }) {
  const { before, after } = view;
  const size = before.total === after.total ? `${before.total}-word` : 'short';
  return (
    <section className={clsx('flex flex-col gap-6 bg-paper p-6 sm:p-7 lg:flex-row lg:items-center lg:justify-between', className)}>
      <div>
        <h2 className="font-display font-semibold">
          <span className="block text-xl text-ink-soft">
            Target-pattern words<span className="sr-only">:</span>
          </span>
          <span className="mt-1 block text-6xl leading-tight tracking-tight tabular-nums">
            {before.correct}/{before.total}
            <span aria-hidden className="px-3 text-ink-soft">→</span>
            <span className="sr-only"> to </span>
            {after.correct}/{after.total}
          </span>
        </h2>
        <p className="mt-2 text-sm text-ink-soft">Two {size} checks in one session. A signal, not a test.</p>
      </div>
      <div className="grid grid-cols-[auto_1fr] items-center gap-x-4 gap-y-3">
        <WordChips side={before} label="Before" />
        <WordChips side={after} label="After" />
      </div>
    </section>
  );
}
