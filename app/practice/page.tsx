'use client';

import { Card } from '@/components/ui/Card';
import { useSession } from '@/lib/session';

// Placeholder printable practice book page.
export default function PracticePage() {
  const book = useSession((s) => s.practiceBook);
  return (
    <main className="mx-auto max-w-3xl px-6 py-16">
      <Card className="p-10">
        <h1 className="font-display text-5xl font-semibold">{book?.title ?? "Pip's Practice Book"}</h1>
        <ol className="story-text mt-8 list-decimal pl-10">
          {(book?.sentences ?? []).map((s) => (
            <li key={s}>{s}</li>
          ))}
        </ol>
      </Card>
    </main>
  );
}
