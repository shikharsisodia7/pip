// Small building blocks shared by the report sections.

import clsx from 'clsx';

/** One cell of the report sheet. The sheet draws the rules between cells. */
export function Tile({ title, className, children }: { title: string; className?: string; children: React.ReactNode }) {
  return (
    <section className={clsx('bg-paper p-6 sm:p-7', className)}>
      <h2 className="font-display text-xl font-semibold text-ink">{title}</h2>
      {children}
    </section>
  );
}

/** A word from the story: set in the story typeface on a highlighter mark. */
export function BookWord({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <span className={clsx('rounded-md bg-sun-soft px-2 py-0.5 font-story text-lg leading-snug text-ink', className)}>
      {children}
    </span>
  );
}

export function CheckIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" className={clsx('h-4 w-4', className)} aria-hidden>
      <path d="M3.5 8.5l3 3 6-7" />
    </svg>
  );
}

export function SampleBadge() {
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full border border-sun bg-sun-soft px-3 py-1 font-sans text-sm font-bold text-bark"
      title="These numbers are sample data, not a real reading session."
    >
      <span className="h-2 w-2 rounded-full bg-sun" aria-hidden />
      Sample data
    </span>
  );
}
