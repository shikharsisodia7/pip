'use client';

import { StubScreen } from '@/components/ui/StubScreen';
import { useSession } from '@/lib/session';

export default function Read() {
  const advance = useSession((s) => s.advance);
  return (
    <StubScreen
      title="Read to Pip"
      note="The kid reads page 1 aloud, words light up as they go, and Pip notices which sounds were tricky."
      nextLabel="Let Pip try"
      onNext={advance}
    />
  );
}
