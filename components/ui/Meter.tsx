'use client';
// FROZEN shared UI primitive. Do not edit; ask the bootstrap owner for changes.

import clsx from 'clsx';
import { motion } from 'framer-motion';

export interface MeterProps {
  /** 0..1, clamped. */
  value: number;
  label?: string;
  /** Text shown at the right end of the label row. */
  valueLabel?: string;
  tone?: 'accent' | 'sun' | 'muted';
  height?: number;
  className?: string;
}

const TONES = {
  accent: 'bg-accent',
  sun: 'bg-sun',
  muted: 'bg-ink-soft/40',
};

export function Meter({ value, label, valueLabel, tone = 'accent', height = 20, className }: MeterProps) {
  const v = Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : 0;
  return (
    <div className={clsx('w-full', className)}>
      {(label || valueLabel) && (
        <div className="mb-2 flex items-baseline justify-between text-ink-soft">
          <span className="font-display text-lg">{label}</span>
          {valueLabel && <span className="font-display text-lg text-ink">{valueLabel}</span>}
        </div>
      )}
      <div
        className="w-full overflow-hidden rounded-full bg-line/70"
        style={{ height }}
        role="meter"
        aria-valuemin={0}
        aria-valuemax={1}
        aria-valuenow={v}
        aria-label={label}
      >
        <motion.div
          className={clsx('h-full rounded-full', TONES[tone])}
          initial={{ width: 0 }}
          animate={{ width: `${v * 100}%` }}
          transition={{ type: 'spring', stiffness: 120, damping: 20 }}
        />
      </div>
    </div>
  );
}

export default Meter;
