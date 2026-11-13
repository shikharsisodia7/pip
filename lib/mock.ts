// FROZEN shared helper. Do not edit; ask the bootstrap owner for changes.
// One definition of "mock mode" for the whole app.
//
// Client precedence: ?mock=1 / ?mock=0 in the URL, then the debug panel
// override in localStorage, then NEXT_PUBLIC_MOCK.
// Server routes cannot see the URL, so the client sends MOCK_HEADER on every
// request (lib/api.ts does this) and routes call isMockRequest(req).

export const MOCK_HEADER = 'x-pip-mock';
const STORAGE_KEY = 'pip.mock';

const envMock = () => process.env.NEXT_PUBLIC_MOCK === '1';

export function isMock(): boolean {
  if (typeof window === 'undefined') return envMock();
  try {
    const q = new URLSearchParams(window.location.search).get('mock');
    if (q === '1') return true;
    if (q === '0') return false;
    const stored = window.localStorage.getItem(STORAGE_KEY);
    if (stored === '1') return true;
    if (stored === '0') return false;
  } catch {
    // storage can be unavailable; fall through to the env default
  }
  return envMock();
}

/** Debug panel toggle. null clears the override. */
export function setMockOverride(on: boolean | null): void {
  try {
    if (on === null) window.localStorage.removeItem(STORAGE_KEY);
    else window.localStorage.setItem(STORAGE_KEY, on ? '1' : '0');
  } catch {
    // ignore
  }
}

export function mockHeaders(): Record<string, string> {
  return { [MOCK_HEADER]: isMock() ? '1' : '0' };
}

/** Server side: is this request in mock mode? */
export function isMockRequest(req: Request): boolean {
  const h = req.headers.get(MOCK_HEADER);
  if (h === '1') return true;
  if (h === '0') return false;
  return envMock();
}
