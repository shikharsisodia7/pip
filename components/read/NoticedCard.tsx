'use client';

// What Pip noticed after the child reads: a warm note from Pip, the sound to
// listen for next, and the button that hands the book to Pip. Never a score.

import { motion } from 'framer-motion';
import { BigButton } from '@/components/ui';
import type { DiagnoseResponse } from '@/lib/types';

/** Shown when Pip's notes are not back in time. */
const FALLBACK_MESSAGE = 'Pip noticed how carefully you read. Thank you!';

export function NoticedCard({ diagnosis, onNext }: { diagnosis?: DiagnoseResponse; onNext: () => void }) {
  const message = diagnosis?.kidMessage?.trim() || FALLBACK_MESSAGE;
  const top = diagnosis?.patterns?.[0];
  const leadsWithNoticed = /^pip noticed/i.test(message);
  return (
    <section
      aria-live="polite"
      className="relative flex w-full max-w-[860px] flex-col items-center gap-6 rounded-card border border-line bg-paper px-8 py-7 text-center shadow-soft md:flex-row md:gap-10 md:pl-10 md:text-left"
    >
      {/* speech bubble tail, pointing up at Pip on the corner of the book */}
      <span aria-hidden className="absolute -top-[11px] right-[52px] hidden size-5 rotate-45 rounded-tl-[5px] border-t border-l border-line bg-paper md:block" />
      <div className="flex-1">
        {!leadsWithNoticed && <p className="font-display text-xl font-medium text-accent-deep">Pip noticed</p>}
        <p className="font-display text-[1.75rem] leading-snug text-ink">{message}</p>
        {top && (
          <motion.p
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.35, duration: 0.3 }}
            className="mt-2 text-xl text-ink-soft"
          >
            Listen for <span className="font-bold text-accent-deep">{top.kidLabel}</span> when Pip reads.
          </motion.p>
        )}
      </div>
      <BigButton onClick={onNext} className="shrink-0">
        Let Pip try
      </BigButton>
    </section>
  );
}

export default NoticedCard;
