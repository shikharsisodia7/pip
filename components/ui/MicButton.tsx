'use client';
// FROZEN shared UI primitive. Do not edit; ask the bootstrap owner for changes.
// idle: tap to start listening. listening: pulsing, tap to stop. disabled: Pip is talking.

import clsx from 'clsx';
import { AnimatePresence, motion } from 'framer-motion';

export type MicState = 'idle' | 'listening' | 'disabled';

export interface MicButtonProps {
  state: MicState;
  onClick?: () => void;
  /** Caption under the button. Defaults depend on state. */
  label?: string;
  size?: number;
  className?: string;
}

const DEFAULT_LABELS: Record<MicState, string> = {
  idle: 'Tap to read',
  listening: 'Listening... tap when you finish',
  disabled: 'Pip is talking',
};

function MicIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" className="h-[42%] w-[42%]" aria-hidden>
      <rect x="9" y="2.5" width="6" height="12" rx="3" />
      <path d="M5 11a7 7 0 0 0 14 0" />
      <path d="M12 18v3.5" />
    </svg>
  );
}

function StopIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-[34%] w-[34%]" aria-hidden>
      <rect x="5" y="5" width="14" height="14" rx="4" fill="currentColor" />
    </svg>
  );
}

export function MicButton({ state, onClick, label, size = 120, className }: MicButtonProps) {
  const listening = state === 'listening';
  const disabled = state === 'disabled';
  return (
    <div className={clsx('flex flex-col items-center gap-4', className)}>
      <div className="relative" style={{ width: size, height: size }}>
        <AnimatePresence>
          {listening &&
            [0, 0.6].map((delay) => (
              <motion.span
                key={delay}
                className="absolute inset-0 rounded-full bg-sun"
                initial={{ scale: 1, opacity: 0.55 }}
                animate={{ scale: 1.7, opacity: 0 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 1.4, repeat: Infinity, delay, ease: 'easeOut' }}
              />
            ))}
        </AnimatePresence>
        <motion.button
          type="button"
          onClick={onClick}
          disabled={disabled}
          aria-label={listening ? 'Stop listening' : 'Start listening'}
          aria-pressed={listening}
          whileTap={disabled ? undefined : { scale: 0.94 }}
          animate={listening ? { scale: [1, 1.04, 1] } : { scale: 1 }}
          transition={listening ? { duration: 1.2, repeat: Infinity } : { type: 'spring', stiffness: 400, damping: 25 }}
          className={clsx(
            'relative flex h-full w-full items-center justify-center rounded-full transition-colors',
            'focus-visible:outline-4 focus-visible:outline-offset-4 focus-visible:outline-accent/40',
            listening && 'bg-accent-deep text-white shadow-lift',
            state === 'idle' && 'bg-accent text-white shadow-[0_8px_0_var(--color-accent-deep)]',
            disabled && 'cursor-not-allowed bg-line text-ink-soft',
          )}
        >
          {listening ? <StopIcon /> : <MicIcon />}
        </motion.button>
      </div>
      <p className={clsx('font-display text-xl', disabled ? 'text-ink-soft' : 'text-ink')} aria-live="polite">
        {label ?? DEFAULT_LABELS[state]}
      </p>
    </div>
  );
}

export default MicButton;
