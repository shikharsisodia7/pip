'use client';

import { StubScreen } from '@/components/ui/StubScreen';
import { useSession } from '@/lib/session';

export default function Report() {
  const reset = useSession((s) => s.reset);
  return (
    <StubScreen
      title="What Pip learned"
      note="The parent and teacher report: reading, patterns, mistakes caught, and expression."
      nextLabel="Start over"
      onNext={reset}
    />
  );
}
