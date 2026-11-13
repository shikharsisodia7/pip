// FROZEN shared session store. Do not edit; ask the bootstrap owner for changes.
//
// Who writes what:
//   Oliver's side: probePre, read, diagnosis, baselineProsody, probePost, practiceBook
//   Pip side:      pipPlan, catches, expression
// Anyone may call setDebug and registerDebugAction.

import { create } from 'zustand';
import { getDemoBook } from './books';
import type {
  Book, CatchResult, DiagnoseResponse, ExpressionResult, Phase, PipPlan, PracticeBook,
  ProbeResult, ProsodyStats, AlignmentResult, ReadingMetrics, Transcript,
} from './types';

export type DemoPath = '2min' | '3min' | 'full';

export interface DebugAction { label: string; run: () => void }

export interface Session {
  phase: Phase;
  demoPath: DemoPath;
  book: Book; readPageIndex: number; pipPageIndex: number;
  probePre?: ProbeResult; probePost?: ProbeResult;
  read?: { transcript: Transcript; alignment: AlignmentResult; metrics: ReadingMetrics };
  diagnosis?: DiagnoseResponse;
  baselineProsody?: ProsodyStats | null;
  pipPlan?: PipPlan; catches: CatchResult[];
  expression?: ExpressionResult;
  practiceBook?: PracticeBook;
  debug: Record<string, unknown>;
  debugActions: DebugAction[];
  set(patch: Partial<Session>): void;
  advance(): void; goto(p: Phase): void; reset(): void;
  setDebug(key: string, value: unknown): void;
  registerDebugAction(label: string, run: () => void): () => void;
}

export const PHASE_ORDER: Phase[] = [
  'intro', 'probePre', 'read', 'pipReads', 'expression', 'probePost', 'report',
];

/** Phases visited on a demo path. The 2 minute path skips both probes. */
export function phasesFor(demoPath: DemoPath): Phase[] {
  if (demoPath === '2min') return PHASE_ORDER.filter((p) => p !== 'probePre' && p !== 'probePost');
  return PHASE_ORDER;
}

export function nextPhase(current: Phase, demoPath: DemoPath): Phase {
  const visible = phasesFor(demoPath);
  const start = PHASE_ORDER.indexOf(current);
  for (let i = start + 1; i < PHASE_ORDER.length; i++) {
    if (visible.includes(PHASE_ORDER[i])) return PHASE_ORDER[i];
  }
  return current;
}

function freshData() {
  return {
    phase: 'intro' as Phase,
    book: getDemoBook(),
    readPageIndex: 0,
    pipPageIndex: 1,
    probePre: undefined,
    probePost: undefined,
    read: undefined,
    diagnosis: undefined,
    baselineProsody: undefined,
    pipPlan: undefined,
    catches: [] as CatchResult[],
    expression: undefined,
    practiceBook: undefined,
    debug: {} as Record<string, unknown>,
  };
}

export const useSession = create<Session>()((set, get) => ({
  ...freshData(),
  demoPath: '2min',
  debugActions: [],

  set: (patch) => set(patch),

  advance: () => {
    const { phase, demoPath } = get();
    set({ phase: nextPhase(phase, demoPath) });
  },

  goto: (p) => set({ phase: p }),

  // Keeps demoPath and registered debug actions (mounted components own those).
  reset: () => set({ ...freshData() }),

  setDebug: (key, value) => set((s) => ({ debug: { ...s.debug, [key]: value } })),

  registerDebugAction: (label, run) => {
    set((s) => ({ debugActions: [...s.debugActions.filter((a) => a.label !== label), { label, run }] }));
    return () =>
      set((s) => ({ debugActions: s.debugActions.filter((a) => !(a.label === label && a.run === run)) }));
  },
}));
