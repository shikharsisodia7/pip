// Pulls the one-line, human-readable summary out of eval/results.json.
// The eval script writes it as `summary`; `slideLine` is accepted as an alias.

const KEYS = ['summary', 'slideLine'] as const;
const MAX_LENGTH = 400;

export function extractSummary(results: unknown): string | null {
  if (!results || typeof results !== 'object') return null;
  const record = results as Record<string, unknown>;
  for (const key of KEYS) {
    const value = record[key];
    if (typeof value === 'string' && value.trim()) return value.trim().slice(0, MAX_LENGTH);
  }
  return null;
}
