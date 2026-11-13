'use client';

import Link from 'next/link';
import Owl from '@/components/pip/Owl';
import { BigButton } from '@/components/ui/BigButton';
import { StoryCredit } from '@/components/ui/StoryCredit';
import { getPattern } from '@/lib/patterns';
import { useSession } from '@/lib/session';
import { PatternText } from './PatternText';
import './practice.css';

export default function PracticePage() {
  const book = useSession((s) => s.practiceBook);
  const sourceBook = useSession((s) => s.book);

  if (!book) {
    return (
      <main className="practice-page practice-empty">
        <Owl state="idle" size={112} />
        <p className="practice-eyebrow">A little more reading</p>
        <h1 className="font-display text-4xl font-semibold sm:text-5xl">A story is waiting to begin.</h1>
        <p className="max-w-md text-xl leading-relaxed text-ink-soft">
          Read with Pip, then make a practice book from your report.
        </p>
        <Link href="/" className="practice-back-link">Back to Pip</Link>
      </main>
    );
  }

  const target = getPattern(book.pattern.id);

  return (
    <main className="practice-page">
      <nav className="practice-toolbar" aria-label="Practice book actions">
        <Link href="/" className="practice-back-link">Back to Pip</Link>
        <BigButton size="md" onClick={() => window.print()}>Print</BigButton>
      </nav>

      <article className="practice-sheet" aria-labelledby="practice-title">
        <header className="practice-header">
          <div>
            <p className="practice-eyebrow">Read with Pip</p>
            <h1 id="practice-title" className="practice-title">{book.title}</h1>
            <p className="practice-invitation">A little story for us to read together.</p>
          </div>
          <div className="practice-owl" aria-hidden="true">
            <Owl state="idle" size={96} />
          </div>
        </header>

        <div className="practice-pattern-note">
          <p>Let’s try {target?.kidLabel ?? book.pattern.kidLabel}.</p>
          {target && (
            <p className="practice-example">
              <PatternText text={target.example} patternId={target.id} />
            </p>
          )}
        </div>
        <p className="practice-hint">The bold letters show our pattern.</p>

        <ol className="practice-sentences">
          {book.sentences.map((sentence, index) => (
            <li key={index}>
              <span className="practice-number" aria-hidden="true">{index + 1}</span>
              <p><PatternText text={sentence} patternId={book.pattern.id} /></p>
            </li>
          ))}
        </ol>

        <footer className="practice-footer">
          <p className="practice-encouragement">Thanks for reading with me! <span aria-hidden="true">✦</span></p>
          <div className="practice-credit">
            <p>Our read-aloud book:</p>
            <StoryCredit book={sourceBook} />
          </div>
        </footer>
      </article>
    </main>
  );
}
