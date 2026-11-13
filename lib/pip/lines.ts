// Pip's fixed lines. These are spoken in his natural (expressive) voice; only his
// read-backs of the story are flat. All of them are prefetched on load.

import type { TtsRequest } from '@/lib/types';

export const PIP_LINES = {
  didIGetItRight: '[curious] Did I get that right?',
  howShouldItSound: "[thoughtful] Hmm, I don't think I said that right. How should it sound?",
  showMeAgain: "[curious] Hmm, I still don't get how they feel. Can you show me again?",
  likeThis: '[excited] Ohh! Like this?',
  celebrate1: "[excited] Yay! You're a great teacher!",
  celebrate2: '[happy] Hooray! Thank you for helping me!',
  whichWord: '[curious] Which word did I get wrong?',
  mixedOneUp: '[thoughtful] Hmm, I think I mixed one up. Let me fix it.',
  keepPracticing: "[happy] I'll keep practicing that one!",
} as const;

export type PipLineId = keyof typeof PIP_LINES;

/** The line text without audio tags, for speech bubbles. */
export function lineText(id: PipLineId): string {
  return PIP_LINES[id].replace(/\[[^\]]*\]/g, ' ').replace(/\s+/g, ' ').trim();
}

export function lineRequest(id: PipLineId): TtsRequest {
  return { text: PIP_LINES[id], mode: 'expressive' };
}

export const ALL_LINE_REQUESTS: TtsRequest[] = (Object.keys(PIP_LINES) as PipLineId[]).map(lineRequest);
