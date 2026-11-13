// Sample report data for the debug panel's "Fill report with demo data" action.
// Words are taken from the current book so the sample stays coherent with the
// story on screen. Every object built here is registered, and the report shows
// a "Sample data" label whenever it renders one of them.

import { PATTERNS, getPattern, wordsWithPattern } from '@/lib/patterns';
import { expressionScore } from '@/lib/prosody/score';
import { tokenizeDisplay } from '@/lib/text';
import type {
  AlignedWord, Book, CatchResult, DiagnoseResponse, ExpressionResult, PatternFinding, PipPlan,
  PlantedMistake, ProbeResult, ProsodyStats, ReadingMetrics, Transcript, AlignmentResult,
} from '@/lib/types';

const samples = new WeakSet<object>();

function mark<T extends object>(o: T): T {
  samples.add(o);
  return o;
}

/** True when the value was produced by buildSampleReport. */
export function isSample(value: unknown): boolean {
  return typeof value === 'object' && value !== null && samples.has(value);
}

/** A plausible misreading for each pattern, used only for sample data. */
const MISREAD: Record<string, [RegExp, string]> = {
  ough: [/ough/, 'ow'], igh: [/igh/, 'ig'], ed: [/ed$/, '-ed'], 'silent-e': [/e$/, ''],
  ou: [/ou/, 'o'], ea: [/ea/, 'e'], er: [/er|ir|ur/, 'ar'], ow: [/ow/, 'o'], ai: [/ai|ay/, 'a'],
  oa: [/oa/, 'o'], oo: [/oo/, 'o'], oi: [/oi|oy/, 'o'], ar: [/ar/, 'a'], or: [/or/, 'o'],
  wh: [/^wh/, 'w'], ee: [/ee/, 'e'], th: [/th/, 't'], sh: [/sh/, 's'], ch: [/ch/, 'k'],
};

function misread(word: string, patternId: string): string {
  const rule = MISREAD[patternId];
  const out = rule ? word.replace(rule[0], rule[1]) : word;
  return out && out !== word ? out : `${word}-uh`;
}

const presentIn = (text: string) => PATTERNS.filter((p) => wordsWithPattern(text, p.id).length > 0).map((p) => p.id);

function probe(items: [string, string, boolean][]): ProbeResult {
  return mark({
    items: items.map(([word, patternId, correct]) => ({ word, patternId, correct, said: correct ? word : undefined })),
    correctCount: items.filter(([, , c]) => c).length,
  });
}

const SECONDS_PER_WORD = 0.9;

export function buildSampleReport(book: Book, readPageIndex: number, pipPageIndex: number) {
  const readText = book.pages[readPageIndex]?.text ?? book.pages[0]?.text ?? '';
  const pipText = book.pages[pipPageIndex]?.text ?? readText;

  // Patterns the child "found tricky": ones on both pages first, so Pip's
  // planted mistakes practice the same patterns, as in a real session.
  const onRead = presentIn(readText);
  const onPip = new Set(presentIn(pipText));
  const ordered = [...onRead.filter((id) => onPip.has(id)), ...onRead.filter((id) => !onPip.has(id))];
  const findings: PatternFinding[] = ordered.slice(0, 2).map((id) => {
    const p = getPattern(id)!;
    return {
      id, kidLabel: p.kidLabel, teacherLabel: p.teacherLabel, confidence: 0.8,
      evidenceWords: [...new Set(wordsWithPattern(readText, id).map((w) => w.word))].slice(0, 2),
    };
  });
  const diagnosis: DiagnoseResponse = mark({ patterns: findings, kidMessage: 'You read that page so carefully!' });

  // Reading: the first evidence word of each pattern was misread.
  const toMiss = new Map(findings.map((f) => [f.evidenceWords[0], f.id]));
  const tokens = tokenizeDisplay(readText);
  const flagged = new Set<string>();
  const words: AlignedWord[] = tokens.map((t, index) => {
    const patternId = toMiss.get(t.norm);
    const wrong = patternId !== undefined && !flagged.has(t.norm);
    if (wrong) flagged.add(t.norm);
    const start = index * SECONDS_PER_WORD;
    return {
      index, expected: t.norm, status: wrong ? 'substitution' : 'correct',
      said: wrong ? misread(t.norm, patternId) : t.norm,
      start, end: start + SECONDS_PER_WORD * 0.8,
    };
  });
  const alignment: AlignmentResult = { words, insertions: [] };
  const transcript: Transcript = {
    text: words.map((w) => w.said).join(' '),
    words: words.map((w) => ({ text: w.said ?? w.expected, start: w.start!, end: w.end! })),
  };
  const wordsTotal = tokens.length;
  const wordsCorrect = wordsTotal - flagged.size;
  const durationSec = Math.round(wordsTotal * SECONDS_PER_WORD * 100) / 100;
  const metrics: ReadingMetrics = {
    wcpm: durationSec > 0 ? Math.round(wordsCorrect / (durationSec / 60)) : 0,
    accuracyPct: wordsTotal ? Math.round((100 * wordsCorrect) / wordsTotal) : 0,
    wordsCorrect, wordsTotal, durationSec, hesitations: 1, selfCorrections: 0,
  };
  const read = mark({ transcript, alignment, metrics });

  // Pip's page: two planted mistakes on distinct words, the child's patterns first.
  const pipIds = [...findings.map((f) => f.id).filter((id) => onPip.has(id)), ...[...onPip].filter((id) => !findings.some((f) => f.id === id))];
  const mistakes: PlantedMistake[] = [];
  for (const id of pipIds) {
    const w = wordsWithPattern(pipText, id).find((x) => !mistakes.some((m) => m.wordIndex === x.index));
    if (!w) continue;
    const said = misread(w.word, id);
    mistakes.push({
      wordIndex: w.index, sentenceIndex: 0, correct: w.word, misread: said, speakAs: said,
      patternId: id, reaction: 'Oops! Thank you for fixing that.',
    });
    if (mistakes.length === 2) break;
  }
  const pipPlan: PipPlan = mark({
    pageIndex: pipPageIndex,
    sentences: [{ index: 0, text: pipText, spokenText: pipText, wordStart: 0, wordEnd: tokenizeDisplay(pipText).length }],
    mistakes,
  });
  const catches: CatchResult[] = mark(
    mistakes.map((m, i) => ({ wordIndex: m.wordIndex, caught: true, via: i === 0 ? 'voice' : 'tap' })),
  );

  // Expression, scored with the real scoring function on sample voice stats.
  const baseline: ProsodyStats = mark({
    pitchRangeSemitones: 6.2, pitchSdSemitones: 1.6, loudnessSdDb: 3.0, wordsPerSec: 1.1, voicedFrames: 180,
  });
  const attempt: ProsodyStats = {
    pitchRangeSemitones: 12.8, pitchSdSemitones: 3.4, loudnessSdDb: 5.2, wordsPerSec: 1.8, voicedFrames: 90,
  };
  const { score, passed } = expressionScore(attempt, baseline);
  const expression: ExpressionResult = mark({ baseline, attempt, score, passed, attempts: 1, tags: [] });

  return {
    probePre: probe([['sight', 'igh', true], ['cloud', 'ou', false], ['rain', 'ai', true], ['hopped', 'ed', false], ['brought', 'ough', false]]),
    probePost: probe([['light', 'igh', true], ['fought', 'ough', true], ['mouth', 'ou', true], ['bought', 'ough', false], ['tight', 'igh', true]]),
    read, diagnosis, baselineProsody: baseline, pipPlan, catches, expression,
  };
}
