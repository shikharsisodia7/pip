import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { z } from 'zod';
import page1 from '@/fixtures/transcripts/page1-demo.json';
import { getDemoBook } from '@/lib/books';
import { alignWords } from '@/lib/reading/align';
import { computeMetrics } from '@/lib/reading/metrics';
import { MOCK_HEADER } from '@/lib/mock';
import { writeJsonCache } from '@/lib/server/cache';
import type { AlignmentResult, BookPage, DiagnoseResponse, ReadingMetrics, Transcript, TtsRequest } from '@/lib/types';

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

/** Sample rehearsal data, never a measured reader result. Keep fixture timestamps intact. */
const DEMO_PAGE1_TRANSCRIPT = page1 as Transcript;

interface DemoScript {
  markdown: string;
  transcript: Transcript;
  readPage: BookPage;
  pipPage: BookPage;
  alignment: AlignmentResult;
  metrics: ReadingMetrics;
  expectedAlignment?: AlignmentResult;
  expectedDiagnosis?: DiagnoseResponse;
  issues: string[];
}

/** Use the same alignment and metrics as Read so the diagnose cache key matches. */
function demoReading() {
  const book = getDemoBook();
  const readPage = book.pages[0];
  const pipPage = book.pages[1];
  if (!readPage || !pipPage) throw new Error('The demo needs two book pages.');
  const alignment = alignWords(readPage.text, DEMO_PAGE1_TRANSCRIPT);
  return { transcript: DEMO_PAGE1_TRANSCRIPT, readPage, pipPage, alignment, metrics: computeMetrics(alignment) };
}

const alignmentSchema = z.object({
  words: z.array(z.object({
    index: z.number().int().nonnegative(), expected: z.string(),
    status: z.enum(['correct', 'substitution', 'omission', 'selfCorrected']),
    said: z.string().optional(), start: z.number().optional(), end: z.number().optional(),
    hesitationBeforeSec: z.number().optional(),
  })),
  insertions: z.array(z.object({ afterIndex: z.number().int(), said: z.string() })),
});

const diagnosisSchema = z.object({
  patterns: z.array(z.object({
    id: z.string(), kidLabel: z.string(), teacherLabel: z.string(),
    evidenceWords: z.array(z.string()), confidence: z.number().min(0).max(1),
  })),
  kidMessage: z.string(),
});

/** The script may include a JSON block with expectedAlignment and expectedDiagnosis. */
function scriptExpectations(markdown: string) {
  const result: Pick<DemoScript, 'expectedAlignment' | 'expectedDiagnosis'> = {};
  for (const block of markdown.matchAll(/```json\s*\n([\s\S]*?)```/g)) {
    const parsed = JSON.parse(block[1]) as Record<string, unknown>;
    if (parsed.expectedAlignment) result.expectedAlignment = alignmentSchema.parse(parsed.expectedAlignment);
    if (parsed.expectedDiagnosis) result.expectedDiagnosis = diagnosisSchema.parse(parsed.expectedDiagnosis);
  }
  return result;
}

async function loadDemoScript(): Promise<DemoScript> {
  const issues: string[] = [];
  let markdown = '';
  try { markdown = await fs.readFile(path.join(process.cwd(), 'fixtures/demo-script.md'), 'utf8'); } catch { /* Report missing fixture below. */ }
  if (!markdown.trim()) issues.push('fixtures/demo-script.md is missing or empty.');
  let expected: ReturnType<typeof scriptExpectations> = {};
  try { expected = scriptExpectations(markdown); } catch { issues.push('Demo script expectations contain invalid JSON or result shapes.'); }
  // The diagnose owner can also supply the expected response as its standard fixture.
  if (!expected.expectedDiagnosis) {
    try {
      const fixture = await fs.readFile(path.join(process.cwd(), 'fixtures/claude/diagnose.json'), 'utf8');
      expected.expectedDiagnosis = diagnosisSchema.parse(JSON.parse(fixture));
    } catch { /* A script without machine-readable expectations can still be rehearsed. */ }
  }
  return { ...demoReading(), markdown, ...expected, issues };
}

/** Fallback until lib/pip/lines.ts exports PIP_FIXED_LINES as TtsRequest[]. */
const PIP_FIXED_LINES: TtsRequest[] = [
  { text: 'Did I get that right?', mode: 'flat', withTimestamps: true },
  { text: 'How should it sound?', mode: 'flat', withTimestamps: true },
  { text: 'Can you teach me?', mode: 'flat', withTimestamps: true },
];

const planSchema = z.object({
  pageIndex: z.number(),
  sentences: z.array(z.object({ index: z.number(), text: z.string().min(1), spokenText: z.string().min(1), wordStart: z.number(), wordEnd: z.number() })).min(1),
  mistakes: z.array(z.object({ sentenceIndex: z.number(), reaction: z.string().min(1) })),
});
const tagsSchema = z.object({ taggedText: z.string().min(1), tags: z.array(z.string()).min(1) });
const ttsSchema = z.object({ audioUrl: z.string().min(1) });

interface WarmOptions {
  baseUrl: string;
  mock: boolean;
  fixedLines: TtsRequest[];
  fetch?: typeof fetch;
  now?: () => number;
  onAsset?: (asset: WarmAsset) => void;
}

/** Calls the routes themselves. Their caches remain the only source of generated assets. */
async function warmDemoPath(script: DemoScript, options: WarmOptions): Promise<WarmSummary> {
  const request = options.fetch ?? fetch;
  const now = options.now ?? (() => performance.now());
  const start = now();
  const assets: WarmAsset[] = [];
  const issues = [...script.issues];
  const base = new URL(options.baseUrl);
  if (!['http:', 'https:'].includes(base.protocol)) throw new Error('BASE_URL must use http or https.');
  const completed = new Map<string, unknown>();

  async function replay<T>(label: string, route: string, body: unknown, schema: z.ZodType<T>, audio = false): Promise<T | undefined> {
    const serialized = JSON.stringify(body);
    const key = `${route}:${serialized}`;
    if (completed.has(key)) return completed.get(key) as T | undefined;
    let bytes = 0;
    async function call(): Promise<T> {
      const signal = AbortSignal.timeout(60000);
      let response: Response;
      try {
        response = await request(new URL(route, base), {
          method: 'POST', headers: { 'content-type': 'application/json', [MOCK_HEADER]: options.mock ? '1' : '0' },
          body: serialized, cache: 'no-store', signal,
        });
      } catch { throw new Error('request failed or timed out'); }
      const buffer = await response.arrayBuffer();
      bytes += buffer.byteLength;
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      let value: T;
      try { value = schema.parse(JSON.parse(new TextDecoder().decode(buffer))); } catch {
        throw new Error(audio ? 'missing audio or invalid TTS response' : 'invalid response shape');
      }
      if (audio) {
        const audioUrl = (value as { audioUrl: string }).audioUrl;
        const url = new URL(audioUrl, base);
        if (!['http:', 'https:', 'data:'].includes(url.protocol)) throw new Error('audio URL cannot be replayed');
        let audioResponse: Response;
        try { audioResponse = await request(url, { cache: 'no-store', signal }); } catch { throw new Error('audio request failed'); }
        const sound = await audioResponse.arrayBuffer();
        // Inline audio was already counted in the JSON response bytes.
        if (url.protocol !== 'data:') bytes += sound.byteLength;
        if (!audioResponse.ok || !sound.byteLength || !/^(audio\/|application\/octet-stream)/i.test(audioResponse.headers.get('content-type') ?? '')) {
          throw new Error('audio asset is empty, unavailable, or not audio');
        }
      }
      return value;
    }
    let reason: string | undefined;
    let value: T | undefined;
    try { await call(); } catch (error) { reason = error instanceof Error ? error.message : 'request failed'; }
    const secondStart = now();
    try { value = await call(); } catch (error) { reason = error instanceof Error ? error.message : 'request failed'; }
    const elapsed = now() - secondStart;
    const cached = !reason && elapsed < CACHE_HIT_MS;
    const asset: WarmAsset = {
      label, route, cached, bytes, secondMs: Math.round(elapsed * 10) / 10,
      ...(!cached ? { reason: reason ?? `second request took ${Math.round(elapsed)} ms` } : {}),
    };
    assets.push(asset);
    options.onAsset?.(asset);
    completed.set(key, value);
    return value;
  }

  const diagnosis = await replay('Reading patterns', '/api/diagnose', {
    pageText: script.readPage.text, alignment: script.alignment, metrics: script.metrics,
  }, diagnosisSchema);
  if (script.expectedAlignment) {
    const compact = (alignment: DemoScript['alignment']) => ({
      words: alignment.words.map(({ index, expected, status, said }) => ({ index, expected, status, ...(said ? { said } : {}) })),
      insertions: alignment.insertions,
    });
    if (JSON.stringify(compact(script.expectedAlignment)) !== JSON.stringify(compact(script.alignment))) issues.push('Alignment differs from the scripted expectation.');
  }
  if (diagnosis && script.expectedDiagnosis) {
    const ids = (value: typeof diagnosis) => value.patterns.map((pattern) => pattern.id).sort().join(',');
    if (ids(diagnosis) !== ids(script.expectedDiagnosis)) issues.push('Pattern findings differ from the scripted expectation.');
  }
  const plan = diagnosis ? await replay('Pip mistake plan', '/api/pip-mistakes', {
    pageIndex: script.pipPage.index, pageText: script.pipPage.text, patterns: diagnosis.patterns,
  }, planSchema) : undefined;
  if (!plan) issues.push('Pip sentences and reactions could not be warmed without a valid mistake plan.');
  else if (!plan.mistakes.length) issues.push('The Pip plan has no planted mistake for the demo.');

  const ttsRequests: { label: string; body: TtsRequest }[] = [];
  for (const sentence of plan?.sentences ?? []) {
    ttsRequests.push({ label: `Pip sentence ${sentence.index + 1}`, body: { text: sentence.spokenText, mode: 'flat', withTimestamps: true } });
    ttsRequests.push({ label: `Correct reread ${sentence.index + 1}`, body: { text: sentence.text, mode: 'flat', withTimestamps: true } });
  }
  for (const [index, mistake] of (plan?.mistakes ?? []).entries()) {
    ttsRequests.push({ label: `Catch reaction ${index + 1}`, body: { text: mistake.reaction, mode: 'flat', withTimestamps: true } });
  }
  const line = script.pipPage.emotionLine;
  if (line) {
    const tags = await replay('Expression tags', '/api/expression-tags', { line, context: script.pipPage.text }, tagsSchema);
    ttsRequests.push({ label: 'Emotion line, flat', body: { text: line.text, mode: 'flat', withTimestamps: true } });
    if (tags) ttsRequests.push({ label: 'Emotion line, expressive', body: { text: tags.taggedText, mode: 'expressive' } });
    else issues.push('The expressive emotion line could not be warmed without expression tags.');
  } else issues.push('The demo page has no emotion line.');
  options.fixedLines.forEach((body, index) => ttsRequests.push({ label: `Fixed Pip line ${index + 1}`, body }));
  // Sequential requests avoid competing with live speech for provider concurrency.
  for (const { label, body } of ttsRequests) await replay(label, '/api/tts', body, ttsSchema, true);

  const hits = assets.filter((asset) => asset.cached).length;
  const misses = assets.length - hits;
  return {
    version: 1, ok: assets.length > 0 && misses === 0 && issues.length === 0,
    mode: options.mock ? 'mock' : 'live', checkedAt: new Date().toISOString(), thresholdMs: CACHE_HIT_MS,
    hits, misses, totalBytes: assets.reduce((sum, asset) => sum + asset.bytes, 0),
    durationMs: Math.round(now() - start), issues, assets,
  };
}

async function writeDemoStatus(summary: WarmSummary): Promise<void> {
  await writeJsonCache('', 'demo-status', warmSummarySchema.parse(summary));
}

const requestSchema = z.object({ text: z.string().min(1), mode: z.enum(['flat', 'expressive']), withTimestamps: z.boolean().optional() });

async function fixedLines() {
  const file = path.join(process.cwd(), 'lib/pip/lines.ts');
  try { await fs.access(file); } catch { return PIP_FIXED_LINES; }
  const lines = await import(pathToFileURL(file).href) as { PIP_FIXED_LINES?: unknown };
  return z.array(requestSchema).min(1).parse(lines.PIP_FIXED_LINES);
}

async function main() {
  const mock = process.env.NEXT_PUBLIC_MOCK === '1';
  const baseUrl = process.env.BASE_URL ?? 'http://localhost:3000';
  const startedAt = performance.now();
  console.log(`Warming the scripted path (${mock ? 'mock' : 'live'}). Cache hit: second identical request under ${CACHE_HIT_MS} ms.`);
  let summary: WarmSummary;
  try {
    summary = await warmDemoPath(await loadDemoScript(), {
      baseUrl, mock, fixedLines: await fixedLines(),
      onAsset: (asset) => console.log(`${asset.cached ? 'HIT ' : 'MISS'} ${asset.label}: ${asset.secondMs} ms, ${asset.bytes} bytes${asset.reason ? ` (${asset.reason})` : ''}`),
    });
  } catch {
    // Do not persist server response bodies, local paths, credentials, or transcript text.
    summary = {
      version: 1, ok: false, mode: mock ? 'mock' : 'live', checkedAt: new Date().toISOString(),
      thresholdMs: CACHE_HIT_MS, hits: 0, misses: 0, totalBytes: 0,
      durationMs: Math.round(performance.now() - startedAt), assets: [],
      issues: ['Warm run could not start. Check BASE_URL, demo fixtures, and lib/pip/lines.ts exports.'],
    };
  }
  await writeDemoStatus(summary);
  for (const issue of summary.issues) console.log(`SETUP ${issue}`);
  console.log(`${summary.hits} hits, ${summary.misses} misses, ${summary.totalBytes} total response bytes. Status saved to .cache/demo-status.json.`);
  if (mock) console.log('Mock rehearsal only. Run with NEXT_PUBLIC_MOCK=0 against the live server before the demo.');
  if (!summary.ok) process.exitCode = 1;
}

void main().catch(() => {
  console.error('Could not write .cache/demo-status.json. Warm run failed.');
  process.exitCode = 1;
});
