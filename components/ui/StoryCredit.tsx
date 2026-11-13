// FROZEN shared UI primitive. Do not edit; ask the bootstrap owner for changes.
// Required on every reading screen: title, author, illustrator, publisher, license.

import clsx from 'clsx';
import type { Book } from '@/lib/types';

export function StoryCredit({ book, className }: { book: Book; className?: string }) {
  const text = `“${book.title}” by ${book.author}, illustrated by ${book.illustrator}. ${book.publisher}. ${book.license}.`;
  return (
    <p className={clsx('text-sm text-ink-soft', className)}>
      {book.sourceUrl ? (
        <a href={book.sourceUrl} target="_blank" rel="noreferrer" className="underline decoration-line underline-offset-4 hover:text-ink">
          {text}
        </a>
      ) : (
        text
      )}
    </p>
  );
}

export default StoryCredit;
