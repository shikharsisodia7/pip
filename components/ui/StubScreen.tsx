'use client';
// Placeholder screen used by phase stubs until their owners replace them.

import { BigButton } from './BigButton';
import { Card } from './Card';

export function StubScreen({ title, note, onNext, nextLabel = 'Next' }: {
  title: string;
  note: string;
  onNext: () => void;
  nextLabel?: string;
}) {
  return (
    <main className="mx-auto flex min-h-screen max-w-3xl flex-col items-center justify-center gap-10 px-6 text-center">
      <Card className="w-full p-10">
        <p className="text-sm uppercase tracking-[0.2em] text-ink-soft">Placeholder screen</p>
        <h1 className="mt-3 font-display text-5xl font-semibold">{title}</h1>
        <p className="mt-4 text-xl text-ink-soft">{note}</p>
      </Card>
      <BigButton onClick={onNext}>{nextLabel}</BigButton>
    </main>
  );
}

export default StubScreen;
