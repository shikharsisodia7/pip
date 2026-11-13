// FROZEN shared server helper. Do not edit; ask the bootstrap owner for changes.
//
// claudeJson<T>(): one Claude call that must return JSON matching a zod schema.
// - Mock mode, or no ANTHROPIC_API_KEY: returns the fixture file instead (no network).
// - Live: disk cache keyed by model + system + prompt, so identical calls are free and
//   repeatable. (Current Sonnet models reject non-default sampling parameters, so the
//   cache, not temperature 0, is what makes the demo path deterministic.)
// - Invalid JSON or a schema mismatch gets one corrective retry, then it throws.
//   Every route must catch and fall back to a deterministic answer.

import Anthropic from '@anthropic-ai/sdk';
import fs from 'node:fs/promises';
import path from 'node:path';
import type { z } from 'zod';
import { hashKey, readJsonCache, writeJsonCache } from './cache';

export interface ClaudeJsonOptions<T> {
  /** Short label, used for logs and the default fixture name. */
  name: string;
  system: string;
  prompt: string;
  schema: z.ZodType<T>;
  /** Repo-relative fixture path for mock mode. Default: fixtures/claude/<name>.json */
  fixture?: string;
  /** Pass isMockRequest(req). */
  mock?: boolean;
  maxTokens?: number;
}

export const CLAUDE_MODEL = process.env.CLAUDE_MODEL || 'claude-sonnet-5-5';

let client: Anthropic | null = null;
function getClient(): Anthropic {
  client ??= new Anthropic();
  return client;
}

export async function loadFixture<T>(opts: Pick<ClaudeJsonOptions<T>, 'name' | 'fixture' | 'schema'>): Promise<T> {
  const rel = opts.fixture ?? path.join('fixtures', 'claude', `${opts.name}.json`);
  const raw = await fs.readFile(path.join(process.cwd(), rel), 'utf8');
  return opts.schema.parse(JSON.parse(raw));
}

/** Pulls the first JSON object or array out of a reply, tolerating code fences. */
export function extractJson(text: string): unknown {
  const cleaned = text.replace(/```(?:json)?/gi, '').trim();
  const start = cleaned.search(/[[{]/);
  if (start < 0) throw new Error('no JSON in reply');
  const open = cleaned[start];
  const close = open === '{' ? '}' : ']';
  const end = cleaned.lastIndexOf(close);
  if (end <= start) throw new Error('unterminated JSON in reply');
  return JSON.parse(cleaned.slice(start, end + 1));
}

export async function claudeJson<T>(opts: ClaudeJsonOptions<T>): Promise<T> {
  if (opts.mock || !process.env.ANTHROPIC_API_KEY) {
    return loadFixture(opts);
  }

  const key = hashKey(CLAUDE_MODEL, opts.system, opts.prompt);
  const cached = await readJsonCache<unknown>('claude', key);
  if (cached !== null) {
    const parsed = opts.schema.safeParse(cached);
    if (parsed.success) return parsed.data;
  }

  const system = `${opts.system}\n\nReply with a single JSON value only. No prose, no code fences.`;
  const messages: Anthropic.MessageParam[] = [{ role: 'user', content: opts.prompt }];
  let lastError: unknown = null;

  for (let attempt = 0; attempt < 2; attempt++) {
    const res = await getClient().messages.create({
      model: CLAUDE_MODEL,
      max_tokens: opts.maxTokens ?? 2000,
      system,
      messages,
      output_config: { effort: 'low' },
    });
    if (res.stop_reason === 'refusal') throw new Error(`claudeJson(${opts.name}): refused`);

    const text = res.content
      .filter((b): b is Anthropic.TextBlock => b.type === 'text')
      .map((b) => b.text)
      .join('');

    try {
      const value = opts.schema.parse(extractJson(text));
      await writeJsonCache('claude', key, value);
      return value;
    } catch (err) {
      lastError = err;
      messages.push(
        { role: 'assistant', content: text || '(empty)' },
        { role: 'user', content: `That reply was not valid: ${String(err).slice(0, 400)}. Reply with only the corrected JSON.` },
      );
    }
  }
  throw new Error(`claudeJson(${opts.name}) failed: ${String(lastError)}`);
}
