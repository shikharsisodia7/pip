import { fuzzyEqual, normalizeToken, tokenizeDisplay } from '@/lib/text';
import type { AlignmentResult, AlignedWord, Transcript, WordStatus } from '@/lib/types';

interface Step {
  status: WordStatus | 'insertion';
  spokenCount: number;
}

function isFalseStart(attempt: string, expected: string): boolean {
  const prefix = attempt.replace(/'/g, '');
  const word = expected.replace(/'/g, '');
  return prefix.length > 0 && prefix.length < word.length && word.startsWith(prefix);
}

/** Sequence alignment with one-word retries and repeated correct words. */
export function alignWords(expectedText: string, transcript: Transcript): AlignmentResult {
  const expected = tokenizeDisplay(expectedText);
  const spoken = transcript.words
    .map((word) => ({ ...word, norm: normalizeToken(word.text) }))
    .filter((word) => word.norm.length > 0);
  const matches = expected.map((word) => spoken.map((said) => fuzzyEqual(word.norm, said.norm)));
  const costs = Array.from({ length: expected.length + 1 }, () =>
    Array<number>(spoken.length + 1).fill(0));
  const steps = Array.from({ length: expected.length + 1 }, () =>
    Array<Step | undefined>(spoken.length + 1));

  // Work backwards so backtracing can follow the page in reading order.
  for (let i = expected.length; i >= 0; i--) {
    for (let j = spoken.length; j >= 0; j--) {
      if (i === expected.length && j === spoken.length) continue;
      let bestCost = Infinity;
      const consider = (cost: number, step: Step, preferTie = false) => {
        if (cost < bestCost || (preferTie && cost === bestCost)) {
          bestCost = cost;
          steps[i][j] = step;
        }
      };

      if (i < expected.length && j < spoken.length) {
        consider(costs[i + 1][j + 1] + (matches[i][j] ? 0 : 1), {
          status: matches[i][j] ? 'correct' : 'substitution',
          spokenCount: 1,
        });

        // A run may cover one page word, but separate page occurrences still
        // win whenever consuming the run would leave an expected word unread.
        const considerRun = (firstMatch: number, corrected: boolean) => {
          for (let end = firstMatch + 1; end <= spoken.length; end++) {
            consider(costs[i + 1][end] + (corrected ? 1 : 0), {
              status: corrected ? 'selfCorrected' : 'correct',
              spokenCount: end - j,
            }, corrected && matches[i][j] && isFalseStart(spoken[j].norm, expected[i].norm));
            if (end === spoken.length || !matches[i][end]
              || isFalseStart(spoken[end - 1].norm, expected[i].norm)) break;
          }
        };

        if (matches[i][j]) considerRun(j, false);
        if (j + 1 < spoken.length && matches[i][j + 1]
          && (!matches[i][j] || isFalseStart(spoken[j].norm, expected[i].norm))) {
          // An unmatched word immediately before the right word is a retry.
          // Its alignment cost equals an insertion, but it scores as correct.
          considerRun(j + 1, true);
        }
      }
      if (i < expected.length) {
        consider(costs[i + 1][j] + 1, { status: 'omission', spokenCount: 0 });
      }
      if (j < spoken.length) {
        consider(costs[i][j + 1] + 1, { status: 'insertion', spokenCount: 1 });
      }
      costs[i][j] = bestCost;
    }
  }

  const result: AlignmentResult = { words: [], insertions: [] };
  let i = 0;
  let j = 0;
  while (i < expected.length || j < spoken.length) {
    const step = steps[i][j]!;
    if (step.status === 'insertion') {
      // -1 denotes speech before the first page word.
      result.insertions.push({ afterIndex: i - 1, said: spoken[j].norm });
    } else {
      const word: AlignedWord = { index: i, expected: expected[i].norm, status: step.status };
      if (step.status !== 'omission') {
        const matchedIndex = step.status === 'selfCorrected' ? j + 1 : j;
        const matched = spoken[matchedIndex];
        word.start = matched.start;
        word.end = matched.end;
        if (step.status === 'substitution' || step.status === 'selfCorrected') {
          word.said = spoken[j].norm;
        }
        const previous = spoken[matchedIndex - 1];
        if (previous) {
          const gap = matched.start - previous.end;
          if (gap > 0.8 + 1e-9) word.hesitationBeforeSec = gap;
        }
      }
      result.words.push(word);
      i++;
    }
    j += step.spokenCount;
  }
  return result;
}
