'use client';
// FROZEN shared UI primitive. Do not edit; ask the bootstrap owner for changes.

import clsx from 'clsx';
import { motion, type HTMLMotionProps } from 'framer-motion';

export type BigButtonVariant = 'primary' | 'secondary' | 'quiet';

export type BigButtonProps = Omit<HTMLMotionProps<'button'>, 'children'> & {
  variant?: BigButtonVariant;
  size?: 'md' | 'lg';
  children?: React.ReactNode;
};

const VARIANTS: Record<BigButtonVariant, string> = {
  primary: 'bg-accent text-white shadow-[0_6px_0_var(--color-accent-deep)] hover:brightness-110',
  secondary: 'bg-paper text-ink border-2 border-line shadow-[0_6px_0_var(--color-line)] hover:bg-white',
  quiet: 'bg-transparent text-ink-soft hover:text-ink',
};

const SIZES = {
  md: 'h-16 px-7 text-xl',
  lg: 'h-[72px] px-10 text-2xl',
};

export function BigButton({ variant = 'primary', size = 'lg', className, disabled, children, ...rest }: BigButtonProps) {
  return (
    <motion.button
      type="button"
      disabled={disabled}
      whileHover={disabled ? undefined : { y: -2 }}
      whileTap={disabled ? undefined : { y: 3, scale: 0.98 }}
      transition={{ type: 'spring', stiffness: 500, damping: 30 }}
      className={clsx(
        'tap inline-flex select-none items-center justify-center gap-3 rounded-full font-display font-semibold',
        'transition-[filter,background-color,opacity] focus-visible:outline-4 focus-visible:outline-offset-4 focus-visible:outline-accent/40',
        'disabled:cursor-not-allowed disabled:opacity-40',
        VARIANTS[variant],
        SIZES[size],
        className,
      )}
      {...rest}
    >
      {children}
    </motion.button>
  );
}

export default BigButton;
