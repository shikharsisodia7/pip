'use client';

// An open picture book: illustration on the left page, story text on the right.
// Words light up with a highlighter sweep as they are read and the word the
// reader is on gently pulses. Afterwards the highlights fade and the words Pip
// noticed get a soft pencil underline.

import clsx from 'clsx';
import { motion, useReducedMotion } from 'framer-motion';
import { useSyncExternalStore } from 'react';
import type { Token } from '@/lib/text';
import type { BookPage } from '@/lib/types';

export interface StoryBookProps {
  page: BookPage;
  /** tokenizeDisplay(page.text); index i is page word i. */
  words: Token[];
  /** Words before this index have been read. */
  readCount: number;
  /** Word the reader is on now, or null when not listening. */
  currentIndex: number | null;
  /** Page word indexes to underline. */
  underlined?: ReadonlySet<number>;
  /** Reading is over: highlights fade so the underlines stand out. */
  settled?: boolean;
  className?: string;
}

// The block of pages under the open spread, each layer a little narrower.
const PAGE_EDGES = [
  '0 3px 0 -1px var(--color-paper)',
  '0 4px 0 -1px var(--color-line)',
  '0 7px 0 -2px var(--color-paper)',
  '0 8px 0 -2px var(--color-line)',
  '0 11px 0 -3px var(--color-paper)',
  '0 12px 0 -3px var(--color-line)',
].join(', ');

/** Long pages step down to 36px so the spread never overflows. */
const LONG_PAGE_WORDS = 22;

// "Easy read": wider letter and word spacing for readers who find dense text hard.
// Stored per browser; an in-memory value keeps the toggle working without storage.
const EASY_READ_KEY = 'pip-easy-read';
const easyReadListeners = new Set<() => void>();
let easyReadMemory = false;

function readEasyRead(): boolean {
  try {
    const v = window.localStorage.getItem(EASY_READ_KEY);
    if (v !== null) return v === '1';
  } catch {
    // storage unavailable; fall back to memory
  }
  return easyReadMemory;
}

function writeEasyRead(on: boolean): void {
  easyReadMemory = on;
  try {
    window.localStorage.setItem(EASY_READ_KEY, on ? '1' : '0');
  } catch {
    // storage unavailable; memory still holds the choice
  }
  easyReadListeners.forEach((l) => l());
}

function subscribeEasyRead(listener: () => void): () => void {
  easyReadListeners.add(listener);
  const onStorage = (e: StorageEvent) => {
    if (e.key === EASY_READ_KEY) listener();
  };
  window.addEventListener('storage', onStorage);
  return () => {
    easyReadListeners.delete(listener);
    window.removeEventListener('storage', onStorage);
  };
}

function useEasyRead(): boolean {
  return useSyncExternalStore(subscribeEasyRead, readEasyRead, () => false);
}

function storyTextStyle(easy: boolean, long: boolean): React.CSSProperties | undefined {
  if (easy) {
    return {
      letterSpacing: '0.09em',
      wordSpacing: '0.3em',
      lineHeight: 1.95,
      fontWeight: 700,
      ...(long ? { fontSize: '2rem' } : {}),
    };
  }
  return long ? { fontSize: '2.25rem', lineHeight: 1.55 } : undefined;
}

export function StoryBook({ page, words, readCount, currentIndex, underlined, settled = false, className }: StoryBookProps) {
  const reduceMotion = useReducedMotion() ?? false;
  const easyRead = useEasyRead();
  const underlineOrder = underlined ? [...underlined].sort((a, b) => a - b) : [];
  return (
    // Hardcover board peeking out around the pages.
    <div className={clsx('rounded-[26px] bg-bark px-2 pt-2 pb-[22px] shadow-lift sm:px-2.5', className)}>
      <div
        className="grid w-full overflow-hidden rounded-[18px] bg-paper md:grid-cols-[43fr_57fr]"
        style={{ boxShadow: PAGE_EDGES }}
      >
        <Illustration page={page} />

        <div className="relative flex items-center px-8 py-10 sm:px-12 md:min-h-[420px] md:px-14 md:py-14">
          {/* the spine, falling into shadow toward the gutter */}
          <div aria-hidden className="pointer-events-none absolute inset-y-0 left-0 hidden w-16 bg-linear-to-r from-ink/[0.07] to-transparent md:block" />
          <button
            type="button"
            aria-pressed={easyRead}
            onClick={() => writeEasyRead(!easyRead)}
            className={clsx(
              'absolute right-3 top-3 z-10 rounded-full border-2 px-4 py-1.5 font-sans text-base font-bold transition-colors',
              easyRead ? 'border-accent bg-accent-soft text-accent-deep' : 'border-line bg-paper text-ink-soft hover:text-ink',
            )}
          >
            <span aria-hidden className="mr-1 font-story">Aa</span> Easy read
          </button>
          <p
            className="story-text relative text-pretty text-ink"
            style={storyTextStyle(easyRead, words.length > LONG_PAGE_WORDS)}
          >
            {words.map((w, i) => (
              <span key={i}>
                {i > 0 && ' '}
                <StoryWord
                  text={w.display}
                  read={i < readCount}
                  current={i === currentIndex}
                  underlineOrder={underlined?.has(i) ? underlineOrder.indexOf(i) : -1}
                  settled={settled}
                  reduceMotion={reduceMotion}
                />
              </span>
            ))}
          </p>
        </div>
      </div>
    </div>
  );
}

function Illustration({ page }: { page: BookPage }) {
  return (
    <div className="relative h-56 overflow-hidden sm:h-72 md:h-auto" style={{ backgroundColor: page.scene.bg }}>
      {page.imageUrl ? (
        // Plain img: book art may come from any open-licensed host.
        // eslint-disable-next-line @next/next/no-img-element
        <img src={page.imageUrl} alt="" className="absolute inset-0 h-full w-full object-cover" />
      ) : (
        <div aria-hidden className="absolute inset-0 grid place-items-center">
          <div className="absolute size-[72%] rounded-full bg-white/45 blur-3xl" />
          <div className="absolute bottom-[16%] h-[7%] w-[38%] rounded-[50%] bg-ink/[0.07] blur-md" />
          <span className="relative text-[8rem] leading-none sm:text-[10rem]">{page.scene.emoji}</span>
        </div>
      )}
      <div aria-hidden className="pointer-events-none absolute inset-y-0 right-0 hidden w-20 bg-linear-to-l from-ink/[0.13] to-transparent md:block" />
      <div aria-hidden className="pointer-events-none absolute inset-y-0 right-0 hidden w-px bg-ink/[0.08] md:block" />
    </div>
  );
}

function StoryWord({ text, read, current, underlineOrder, settled, reduceMotion }: {
  text: string;
  read: boolean;
  current: boolean;
  /** Position among underlined words (for a staggered draw), or -1. */
  underlineOrder: number;
  settled: boolean;
  reduceMotion: boolean;
}) {
  const pulse = current && !reduceMotion;
  return (
    <span className="relative inline-block">
      {/* Highlighter stroke. Opaque and slightly wider than the word so a run of
          read words joins into one swipe; the text sits above it. */}
      <span
        aria-hidden
        className={clsx(
          'absolute -inset-x-[0.16em] top-[0.46em] bottom-[0.24em] z-0 origin-left',
          'rounded-[0.22em_0.4em_0.3em_0.45em/0.35em_0.45em_0.35em_0.5em]',
          'bg-[color-mix(in_srgb,var(--color-sun)_48%,var(--color-paper))]',
          'transition-[transform,opacity] duration-300 ease-out motion-reduce:transition-none',
          read ? 'scale-x-100' : 'scale-x-0',
          settled && 'opacity-0 duration-700',
        )}
      />
      <motion.span
        className={clsx('relative z-[1] inline-block transition-colors duration-200', current ? 'text-accent' : 'text-ink')}
        animate={pulse ? { scale: [1, 1.08, 1] } : { scale: 1 }}
        transition={pulse ? { duration: 1.1, repeat: Infinity, ease: 'easeInOut' } : { duration: 0.2 }}
      >
        {text}
      </motion.span>
      {underlineOrder >= 0 && <PencilUnderline delay={0.25 + underlineOrder * 0.18} reduceMotion={reduceMotion} />}
    </span>
  );
}

function PencilUnderline({ delay, reduceMotion }: { delay: number; reduceMotion: boolean }) {
  return (
    <svg
      aria-hidden
      viewBox="0 0 100 12"
      preserveAspectRatio="none"
      className="pointer-events-none absolute -left-[0.06em] bottom-[0.04em] z-[1] h-[0.3em] w-[calc(100%+0.12em)] overflow-visible text-accent"
    >
      <motion.path
        d="M2 5 C 28 10, 70 10, 98 4"
        fill="none"
        stroke="currentColor"
        strokeWidth={3.5}
        strokeLinecap="round"
        initial={{ pathLength: reduceMotion ? 1 : 0 }}
        animate={{ pathLength: 1 }}
        transition={{ duration: 0.5, delay: reduceMotion ? 0 : delay, ease: 'easeOut' }}
      />
    </svg>
  );
}

export default StoryBook;
