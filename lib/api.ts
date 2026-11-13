// FROZEN shared helper. Do not edit; ask the bootstrap owner for changes.
// Client fetch helpers. Always use these for /api calls so mock mode reaches the server.

import { mockHeaders } from './mock';

export async function postJson<T>(url: string, body: unknown, init?: RequestInit): Promise<T> {
  const res = await fetch(url, {
    method: 'POST',
    ...init,
    headers: { 'content-type': 'application/json', ...mockHeaders(), ...(init?.headers ?? {}) },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${url} failed with ${res.status}`);
  return (await res.json()) as T;
}

export async function getJson<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, {
    ...init,
    headers: { ...mockHeaders(), ...(init?.headers ?? {}) },
    cache: 'no-store',
  });
  if (!res.ok) throw new Error(`${url} failed with ${res.status}`);
  return (await res.json()) as T;
}
