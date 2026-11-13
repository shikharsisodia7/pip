'use client';

import clsx from 'clsx';

export type OwlState = 'idle' | 'listening' | 'speaking' | 'confused' | 'thinking' | 'celebrating';

export interface OwlProps {
  state?: OwlState;
  size?: number;
  className?: string;
}

/** Placeholder owl. Keep the default export and prop names stable. */
export default function Owl({ state = 'idle', size = 160, className }: OwlProps) {
  return (
    <div
      role="img"
      aria-label={`Pip the owl, ${state}`}
      data-state={state}
      className={clsx('flex select-none items-center justify-center', className)}
      style={{ width: size, height: size, fontSize: size * 0.78, lineHeight: 1 }}
    >
      <span aria-hidden>🦉</span>
    </div>
  );
}
