// Mints a single-use realtime Scribe token for the browser.
// The API key stays on the server; the client only ever sees the token.
// Tokens are single use and expire after 15 minutes, so one is minted per
// connect and nothing here is cached.

const TOKEN_URL = 'https://api.elevenlabs.io/v1/single-use-token/realtime_scribe';
const NO_STORE = { 'cache-control': 'no-store' };

function fail(error: string, status: number) {
  return Response.json({ error }, { status, headers: NO_STORE });
}

export async function GET() {
  const apiKey = process.env.ELEVENLABS_API_KEY;
  if (!apiKey) return fail('ELEVENLABS_API_KEY is not set on the server', 503);

  try {
    const res = await fetch(TOKEN_URL, {
      method: 'POST',
      headers: { 'xi-api-key': apiKey },
      cache: 'no-store',
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) {
      const detail = (await res.text().catch(() => '')).slice(0, 200);
      return fail(`token request failed with ${res.status}${detail ? `: ${detail}` : ''}`, 502);
    }
    const body = (await res.json()) as { token?: unknown };
    if (typeof body.token !== 'string' || !body.token) return fail('token missing from response', 502);
    return Response.json({ token: body.token }, { headers: NO_STORE });
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    return fail(`token request failed: ${reason}`, 502);
  }
}
