// Pure helpers that turn session slices into what the report shows.
// Each returns null when its slice is missing or unusable, so the report hides
// that section instead of showing NaN or a number that was never measured.

import { getPattern } from '@/lib/patterns';
import { MIN_ATTEMPT_VOICED_FRAMES, MIN_BASELINE_VOICED_FRAMES } from '@/lib/prosody/score';
import type {
  CatchResult, DiagnoseResponse, ExpressionResult, PatternFinding, PipPlan, ProbeResult, ReadingMetrics,
} from '@/lib/types';

const isNum = (n: unknown): n is number => typeof n === 'number' && Number.isFinite(n);

// Reading ---------------------------------------------------------------------

export interface ReadingView {
  wcpm?: number;
  accuracyPct?: number;
  wordsCorrect?: number;
  wordsTotal: number;
  durationSec?: number;
}

export function readingView(m?: ReadingMetrics): ReadingView | null {
  if (!m || !isNum(m.wordsTotal) || m.wordsTotal <= 0) return null;
  const wcpm = isNum(m.wcpm) && m.wcpm > 0 ? Math.round(m.wcpm) : undefined;
  const accuracyPct = isNum(m.accuracyPct) && m.accuracyPct >= 0 && m.accuracyPct <= 100
    ? Math.round(m.accuracyPct) : undefined;
  if (wcpm === undefined && accuracyPct === undefined) return null;
  return {
    wcpm,
    accuracyPct,
    wordsTotal: Math.round(m.wordsTotal),
    wordsCorrect: isNum(m.wordsCorrect) && m.wordsCorrect >= 0 && m.wordsCorrect <= m.wordsTotal
      ? Math.round(m.wordsCorrect) : undefined,
    durationSec: isNum(m.durationSec) && m.durationSec > 0 ? Math.round(m.durationSec) : undefined,
  };
}

// Mistakes caught ---------------------------------------------------------------

export type CatchOutcome = 'voice' | 'tap' | 'missed';

export interface MistakeRow {
  wordIndex: number;
  correct: string;
  misread: string;
  patternId: string;
  outcome: CatchOutcome;
}

export interface MistakesView { caught: number; total: number; rows: MistakeRow[] }

/**
 * Only mistakes Pip actually read count as planted: a mistake with no catch
 * record was never presented (for example, a sentence the short path skips).
 */
export function mistakesView(plan: PipPlan | undefined, catches: CatchResult[] | undefined): MistakesView | null {
  if (!plan?.mistakes?.length || !catches?.length) return null;
  const rows: MistakeRow[] = [];
  for (const m of plan.mistakes) {
    const records = catches.filter((c) => c.wordIndex === m.wordIndex);
    if (!records.length) continue;
    const hit = records.find((c) => c.caught);
    rows.push({
      wordIndex: m.wordIndex,
      correct: m.correct,
      misread: m.misread,
      patternId: m.patternId,
      outcome: hit ? (hit.via === 'tap' ? 'tap' : 'voice') : 'missed',
    });
  }
  if (!rows.length) return null;
  return { caught: rows.filter((r) => r.outcome !== 'missed').length, total: rows.length, rows };
}

// Patterns ----------------------------------------------------------------------

export interface PatternLine { id: string; teacherLabel: string; words: string[] }
export interface PatternsView { needsPractice: PatternLine[]; practicedToday: PatternLine[] }

const uniq = (xs: string[]) => [...new Set(xs.filter(Boolean))];

export function patternsView(diagnosis: DiagnoseResponse | undefined, mistakes: MistakesView | null): PatternsView | null {
  const needsPractice: PatternLine[] = [];
  for (const p of diagnosis?.patterns ?? []) {
    if (needsPractice.some((x) => x.id === p.id)) continue;
    const teacherLabel = p.teacherLabel || getPattern(p.id)?.teacherLabel;
    if (!teacherLabel) continue;
    needsPractice.push({ id: p.id, teacherLabel, words: uniq(p.evidenceWords ?? []).slice(0, 3) });
    if (needsPractice.length === 3) break;
  }

  const practicedToday: PatternLine[] = [];
  for (const row of mistakes?.rows ?? []) {
    const existing = practicedToday.find((x) => x.id === row.patternId);
    if (existing) {
      existing.words = uniq([...existing.words, row.correct]);
      continue;
    }
    const teacherLabel = getPattern(row.patternId)?.teacherLabel;
    if (teacherLabel) practicedToday.push({ id: row.patternId, teacherLabel, words: [row.correct] });
  }

  if (!needsPractice.length && !practicedToday.length) return null;
  return { needsPractice, practicedToday };
}

/** The pattern the practice book should focus on. */
export function topPattern(diagnosis: DiagnoseResponse | undefined, mistakes: MistakesView | null): PatternFinding | null {
  const first = diagnosis?.patterns?.[0];
  if (first) return first;
  const row = mistakes?.rows[0];
  const p = row ? getPattern(row.patternId) : undefined;
  if (!row || !p) return null;
  return { id: p.id, kidLabel: p.kidLabel, teacherLabel: p.teacherLabel, evidenceWords: [row.correct], confidence: 0 };
}

// Expression --------------------------------------------------------------------

export interface ExpressionBars {
  /** The child's own reading voice. The score scale puts it at 1. */
  baseline: number;
  attempt: number;
  /** Shared full-bar value, so both bars use one scale. */
  scale: number;
}

export interface ExpressionView { passed: boolean; bars: ExpressionBars | null }

export function expressionView(e?: ExpressionResult): ExpressionView | null {
  if (!e || !isNum(e.score)) return null;
  if (!e.attempt || !(e.attempt.voicedFrames >= MIN_ATTEMPT_VOICED_FRAMES)) return null;
  const hasBaseline = !!e.baseline && e.baseline.voicedFrames >= MIN_BASELINE_VOICED_FRAMES;
  const attempt = Math.max(0, e.score);
  return {
    passed: !!e.passed,
    bars: hasBaseline ? { baseline: 1, attempt, scale: Math.max(2, attempt * 1.15) } : null,
  };
}

// Before and after word checks ----------------------------------------------------

export interface ProbeSide { correct: number; total: number; items: { word: string; correct: boolean }[] }
export interface ProbeView { before: ProbeSide; after: ProbeSide }

function probeSide(r?: ProbeResult): ProbeSide | null {
  const items = (r?.items ?? []).filter((i) => i && typeof i.word === 'string' && i.word);
  if (!items.length) return null;
  return {
    correct: items.filter((i) => i.correct).length,
    total: items.length,
    items: items.map((i) => ({ word: i.word, correct: !!i.correct })),
  };
}

export function probeView(pre?: ProbeResult, post?: ProbeResult): ProbeView | null {
  const before = probeSide(pre);
  const after = probeSide(post);
  return before && after ? { before, after } : null;
}
