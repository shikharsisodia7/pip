'use client';

import { StubScreen } from '@/components/ui/StubScreen';
import { useSession } from '@/lib/session';

export default function Probe() {
  const advance = useSession((s) => s.advance);
  const phase = useSession((s) => s.phase);
  return (
    <StubScreen
      title={phase === 'probePost' ? 'One more quick check' : 'A quick warm up'}
      note="Five word cards, one mic press. The kid reads all five and Pip says thanks."
      onNext={advance}
    />
  );
}
