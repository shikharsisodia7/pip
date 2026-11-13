'use client';

import { AnimatePresence, motion } from 'framer-motion';
import type { ComponentType } from 'react';
import Expression from '@/components/phases/Expression';
import Intro from '@/components/phases/Intro';
import PipReads from '@/components/phases/PipReads';
import Probe from '@/components/phases/Probe';
import Read from '@/components/phases/Read';
import Report from '@/components/phases/Report';
import { useSession } from '@/lib/session';
import type { Phase } from '@/lib/types';

const SCREENS: Record<Phase, ComponentType> = {
  intro: Intro,
  probePre: Probe,
  read: Read,
  pipReads: PipReads,
  expression: Expression,
  probePost: Probe,
  report: Report,
};

/** PhaseRouter: one screen per session phase. */
export default function Home() {
  const phase = useSession((s) => s.phase);
  const Screen = SCREENS[phase];
  return (
    <AnimatePresence mode="wait">
      <motion.div
        key={phase}
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -12 }}
        transition={{ duration: 0.25 }}
      >
        <Screen />
      </motion.div>
    </AnimatePresence>
  );
}
