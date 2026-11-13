import { getDemoBook } from '@/lib/books';
import { PATTERNS, isPatternId } from '@/lib/patterns';
import { tokenize } from '@/lib/text';
import type { PatternFinding, ProbeItem } from '@/lib/types';
import { PROBE_WORD_BANK } from './bank';

const PRE_PATTERNS = ['ai', 'oa', 'sh', 'silent-e', 'igh'];

function bookWords(): Set<string> {
  const book = getDemoBook();
  return new Set(tokenize([
    book.title,
    ...book.pages.flatMap((page) => [page.text, page.emotionLine?.text ?? '']),
  ].join(' ')));
}

function takeWord(patternId: string, excluded: Set<string>): ProbeItem | undefined {
  const word = PROBE_WORD_BANK[patternId]?.find((candidate) => !excluded.has(candidate));
  if (!word) return;
  excluded.add(word);
  return { word, patternId };
}

function preProbe(excluded: Set<string>): ProbeItem[] {
  const items: ProbeItem[] = [];
  const order = [...new Set([...PRE_PATTERNS, ...PATTERNS.map((pattern) => pattern.id)])];
  for (const id of order) {
    const item = takeWord(id, excluded);
    if (item) items.push(item);
    if (items.length === 5) break;
  }
  return items;
}

/** Repeatable probes, with story words excluded from the current book at call time. */
export function pickProbeWords(kind: 'pre' | 'post', patterns: PatternFinding[] = []): ProbeItem[] {
  const excluded = bookWords();
  const pre = preProbe(excluded);
  if (kind === 'pre') return pre;

  const ranked = [...new Set(
    patterns
      .filter((pattern) => isPatternId(pattern.id))
      .sort((a, b) => b.confidence - a.confidence)
      .map((pattern) => pattern.id),
  )];
  // Three words for the strongest finding, then two for the next finding.
  // With no findings, revisit the same five patterns using different words.
  const targets = ranked.length
    ? [ranked[0], ranked[0], ranked[0], ranked[1] ?? ranked[0], ranked[1] ?? ranked[0]]
    : pre.map((item) => item.patternId);
  const fallback = [...new Set([...ranked, ...PRE_PATTERNS, ...PATTERNS.map((pattern) => pattern.id)])];

  return targets.flatMap((target) => {
    for (const id of new Set([target, ...fallback])) {
      const item = takeWord(id, excluded);
      if (item) return [item];
    }
    return [];
  });
}
