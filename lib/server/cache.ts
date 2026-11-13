// FROZEN shared server helper. Do not edit; ask the bootstrap owner for changes.
// Disk cache under .cache/ (gitignored). .cache may be a symlink to a shared
// folder so several local checkouts reuse the same Claude and TTS results.

import { createHash } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

export const CACHE_DIR = path.join(process.cwd(), '.cache');

/** Stable short hash of any JSON-serialisable parts. */
export function hashKey(...parts: unknown[]): string {
  return createHash('sha256').update(JSON.stringify(parts)).digest('hex').slice(0, 40);
}

export function cachePath(ns: string, key: string, ext = ''): string {
  return path.join(CACHE_DIR, ns, key + ext);
}

export async function readCache(ns: string, key: string, ext = ''): Promise<Buffer | null> {
  try {
    return await fs.readFile(cachePath(ns, key, ext));
  } catch {
    return null;
  }
}

/** Atomic write (tmp file + rename). Returns the file path. */
export async function writeCache(ns: string, key: string, data: Buffer | string, ext = ''): Promise<string> {
  const file = cachePath(ns, key, ext);
  await fs.mkdir(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.${Date.now()}.tmp`;
  await fs.writeFile(tmp, data);
  await fs.rename(tmp, file);
  return file;
}

export async function hasCache(ns: string, key: string, ext = ''): Promise<boolean> {
  try {
    await fs.access(cachePath(ns, key, ext));
    return true;
  } catch {
    return false;
  }
}

export async function readJsonCache<T>(ns: string, key: string): Promise<T | null> {
  const buf = await readCache(ns, key, '.json');
  if (!buf) return null;
  try {
    return JSON.parse(buf.toString('utf8')) as T;
  } catch {
    return null;
  }
}

export async function writeJsonCache(ns: string, key: string, value: unknown): Promise<string> {
  return writeCache(ns, key, JSON.stringify(value, null, 2), '.json');
}
