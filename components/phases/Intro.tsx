'use client';

import { motion } from 'framer-motion';
import Owl from '@/components/pip/Owl';
import { BigButton } from '@/components/ui/BigButton';
import { useSession } from '@/lib/session';

export default function Intro() {
  const advance = useSession((s) => s.advance);
  return (
    <main className="mx-auto flex min-h-screen max-w-3xl flex-col items-center justify-center gap-10 px-6 text-center">
      <motion.div
        initial={{ y: 24, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        transition={{ type: 'spring', stiffness: 120, damping: 14 }}
      >
        <Owl state="idle" size={220} />
      </motion.div>
      <div>
        <h1 className="font-display text-6xl font-semibold tracking-tight">Hi! I&apos;m Pip.</h1>
        <p className="mt-4 text-2xl text-ink-soft">I&apos;m learning to read. Will you be my teacher?</p>
      </div>
      <BigButton onClick={advance}>Let&apos;s read!</BigButton>
    </main>
  );
}
