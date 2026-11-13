// What to do next, and why families and teachers can trust the numbers.

import { PROBE_WORD_BANK } from '@/lib/probe/bank';
import type { PatternFinding, ProbeResult } from '@/lib/types';
import { BookWord, CheckIcon, Tile } from './parts';

/** Three warm up words for a pattern, skipping words the child already saw in a probe. */
export function practiceWords(patternId: string, seen: (ProbeResult | undefined)[]): string[] {
  const bank = PROBE_WORD_BANK[patternId] ?? [];
  const used = new Set(seen.flatMap((p) => p?.items.map((i) => i.word.toLowerCase()) ?? []));
  const fresh = bank.filter((w) => !used.has(w.toLowerCase()));
  return (fresh.length >= 3 ? fresh : bank).slice(0, 3);
}

export function NextSessionTile({ pattern, words }: { pattern: PatternFinding; words: string[] }) {
  return (
    <Tile title="Next session plan">
      <p className="mt-3 text-lg text-ink-soft">
        Keep working on <span className="font-semibold text-ink">{pattern.kidLabel}</span> ({pattern.teacherLabel}).
        A few minutes a day is plenty.
      </p>
      {words.length > 0 && (
        <div className="mt-4 flex flex-wrap items-center gap-2">
          <span className="mr-1 text-sm font-semibold uppercase tracking-wide text-ink-soft">Warm up with</span>
          {words.map((w) => (
            <BookWord key={w}>{w}</BookWord>
          ))}
        </div>
      )}
      <ol className="mt-4 list-decimal space-y-1.5 pl-5 text-lg text-ink">
        <li>Read the warm up words together.</li>
        <li>Open Pip&apos;s Practice Book and read it aloud.</li>
        <li>Read one new page to Pip so he can check what stuck.</li>
      </ol>
    </Tile>
  );
}

const TRUST_POINTS = [
  {
    title: 'Scores are counted, not guessed',
    body: 'Words correct and reading speed come from matching what your child said to the words on the page. An AI never grades your child.',
  },
  {
    title: 'AI only helps with the fun parts',
    body: 'Claude suggests which sounds to practice and writes Pip’s lines. ElevenLabs turns speech into text and gives Pip his voice.',
  },
  {
    title: 'Recordings are not saved',
    body: 'Pip never stores your child’s voice. Speech is sent only to be turned into text, and expression is measured right in the browser.',
  },
  {
    title: 'Real books, openly licensed',
    body: 'Stories come from Pratham Books StoryWeaver under CC BY 4.0. No student records are used.',
  },
];

export function TrustTile({ className }: { className?: string }) {
  return (
    <Tile title="Why you can trust Pip" className={className}>
      <ul className="mt-4 space-y-3">
        {TRUST_POINTS.map((p) => (
          <li key={p.title} className="flex gap-3">
            <CheckIcon className="mt-1.5 shrink-0 text-accent-deep" />
            <div>
              <p className="font-semibold text-ink">{p.title}</p>
              <p className="text-ink-soft">{p.body}</p>
            </div>
          </li>
        ))}
      </ul>
    </Tile>
  );
}
