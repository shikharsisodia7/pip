'use client';

import { StubScreen } from '@/components/ui/StubScreen';
import { useSession } from '@/lib/session';

export default function PipReads() {
  const advance = useSession((s) => s.advance);
  return (
    <StubScreen
      title="Your turn to be the teacher!"
      note="Pip reads the next page flat, makes a mistake on a tricky sound, and the kid catches it by voice."
      onNext={advance}
    />
  );
}
