import { z } from 'zod';
import { readJsonCache } from '@/lib/server/cache';

const CACHE_HIT_MS = 400;

const assetSchema = z.object({
  label: z.string(),
  route: z.string(),
  cached: z.boolean(),
  secondMs: z.number().nonnegative().nullable(),
  bytes: z.number().int().nonnegative(),
  reason: z.string().optional(),
});

const warmSummarySchema = z.object({
  version: z.literal(1),
  ok: z.boolean(),
  mode: z.enum(['mock', 'live']),
  checkedAt: z.iso.datetime(),
  thresholdMs: z.literal(CACHE_HIT_MS),
  hits: z.number().int().nonnegative(),
  misses: z.number().int().nonnegative(),
  totalBytes: z.number().int().nonnegative(),
  durationMs: z.number().nonnegative(),
  issues: z.array(z.string()),
  assets: z.array(assetSchema),
}).refine((s) =>
  s.hits === s.assets.filter((asset) => asset.cached).length &&
  s.misses === s.assets.filter((asset) => !asset.cached).length &&
  s.ok === (s.assets.length > 0 && s.misses === 0 && s.issues.length === 0),
);

type WarmAsset = z.infer<typeof assetSchema>;
type WarmSummary = z.infer<typeof warmSummarySchema>;
type DemoStatus = WarmSummary | { ok: false; reason: string };

export const runtime = 'nodejs';

export async function GET() {
  const saved = await readJsonCache<unknown>('', 'demo-status');
  const parsed = warmSummarySchema.safeParse(saved);
  const summary = saved === null
    ? { ok: false, reason: 'not warmed' }
    : parsed.success ? parsed.data : { ok: false, reason: 'invalid warm status' };
  return Response.json(summary, { headers: { 'Cache-Control': 'no-store' } });
}
