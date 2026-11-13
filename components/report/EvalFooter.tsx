'use client';

import { useEffect, useState } from 'react';
import { getJson } from '@/lib/api';

/** Shows the listening evaluation's summary line, only when one exists. */
export function EvalFooter({ className }: { className?: string }) {
  const [summary, setSummary] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    getJson<{ summary: string | null }>('/api/eval-summary')
      .then((r) => { if (live) setSummary(typeof r.summary === 'string' && r.summary ? r.summary : null); })
      .catch(() => {});
    return () => { live = false; };
  }, []);

  if (!summary) return null;
  return (
    <aside className={className}>
      <h2 className="font-display text-lg font-semibold">How reliable is Pip&apos;s listening?</h2>
      <p className="mt-1 max-w-3xl text-ink-soft">{summary}</p>
    </aside>
  );
}

export default EvalFooter;
