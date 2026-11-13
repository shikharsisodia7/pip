'use client';

import { StubScreen } from '@/components/ui/StubScreen';
import { useSession } from '@/lib/session';

export default function Expression() {
  const advance = useSession((s) => s.advance);
  return (
    <StubScreen
      title="How should it sound?"
      note="Pip reads an emotional line flat, the kid performs it, and Pip learns to read it with feeling."
      onNext={advance}
    />
  );
}
