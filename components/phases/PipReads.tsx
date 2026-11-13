'use client';

// Checkpoint version: Pip reads the next page flat with word highlighting.
// The full catch-the-mistake loop replaces this.

import { useEffect, useMemo, useState } from 'react';
import clsx from 'clsx';
import { BigButton, Card, StoryCredit } from '@/components/ui';
import Owl from '@/components/pip/Owl';
import { useSession } from '@/lib/session';
import { tokenizeDisplay } from '@/lib/text';
import { flat, prefetch, speak } from '@/lib/pip/tts';
import { ALL_LINE_REQUESTS } from '@/lib/pip/lines';
import { play, useIsSpeaking } from '@/lib/pip/player';

export default function PipReads() {
  const { advance, book, pipPageIndex } = useSession();
  const page = book.pages[pipPageIndex] ?? book.pages[book.pages.length - 1];
  const words = useMemo(() => tokenizeDisplay(page.text), [page.text]);
  const [lit, setLit] = useState(-1);
  const speaking = useIsSpeaking();

  useEffect(() => {
    void prefetch([flat(page.text), ...ALL_LINE_REQUESTS]);
  }, [page.text]);

  const readAloud = async () => {
    setLit(-1);
    const resp = await speak(flat(page.text));
    play(resp, { onWord: (i) => setLit(i) });
  };

  return (
    <main className="mx-auto flex min-h-screen max-w-5xl flex-col gap-6 px-6 py-10">
      <h1 className="font-display text-4xl text-ink">Your turn to be the teacher!</h1>
      <Card className="flex flex-col items-center gap-6 p-8 md:flex-row" style={{ background: page.scene.bg }}>
        <Owl state={speaking ? 'speaking' : 'idle'} size={180} />
        <p className="story-text">
          {words.map((w, i) => (
            <span
              key={i}
              className={clsx('rounded-xl px-1 transition-colors duration-150', i <= lit && 'bg-sun-soft', i === lit && 'bg-sun')}
            >
              {w.display}{' '}
            </span>
          ))}
        </p>
      </Card>
      <div className="flex gap-4">
        <BigButton onClick={readAloud} disabled={speaking}>Hear Pip read</BigButton>
        <BigButton variant="secondary" onClick={advance}>Next</BigButton>
      </div>
      <StoryCredit book={book} />
    </main>
  );
}
