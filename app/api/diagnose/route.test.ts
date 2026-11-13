import { beforeEach, describe, expect, it, vi } from 'vitest';
import fixture from '@/fixtures/claude/diagnose-demo.json';
import { claudeJson } from '@/lib/server/claudeJson';
import type { DiagnoseResponse } from '@/lib/types';
import { POST } from './route';

vi.mock('@/lib/server/claudeJson', () => ({ claudeJson: vi.fn() }));

// Synthetic request metrics for route tests only.
const sampleRequest = {
  pageText: 'She looked out.',
  alignment: {
    words: [
      { index: 0, expected: 'she', status: 'correct' },
      { index: 1, expected: 'looked', status: 'substitution', said: 'look' },
      { index: 2, expected: 'out', status: 'correct' },
    ],
    insertions: [],
  },
  metrics: { wcpm: 40, accuracyPct: 67, wordsCorrect: 2, wordsTotal: 3, durationSec: 3, hesitations: 0, selfCorrections: 0 },
};

function request(body: unknown = sampleRequest) {
  return new Request('http://localhost/api/diagnose', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-pip-mock': '1' },
    body: JSON.stringify(body),
  });
}

beforeEach(() => {
  vi.mocked(claudeJson).mockReset();
  vi.mocked(claudeJson).mockResolvedValue(fixture);
});

describe('POST /api/diagnose', () => {
  it('passes mock mode, the fixture, page, miscues, and candidate ids to Claude', async () => {
    const response = await POST(request());
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(fixture);
    const options = vi.mocked(claudeJson).mock.calls[0][0];
    expect(options).toMatchObject({ name: 'diagnose', fixture: 'fixtures/claude/diagnose-demo.json', mock: true });
    expect(JSON.parse(options.prompt)).toMatchObject({
      pageText: sampleRequest.pageText,
      miscues: [{ expected: 'looked', said: 'look', candidatePatternIds: ['ed', 'oo'] }],
      candidates: [{ id: 'ed', count: 1 }, { id: 'oo', count: 1 }],
    });
  });

  it('returns deterministic ranking if Claude throws', async () => {
    vi.mocked(claudeJson).mockRejectedValue(new Error('Unavailable'));
    const response = await POST(request());
    expect(response.status).toBe(200);
    const body: DiagnoseResponse = await response.json();
    expect(body.patterns.map((pattern) => pattern.id)).toEqual(['ed', 'oo']);
    expect(body.patterns[0].evidenceWords).toEqual(['looked']);
  });

  it.each([null, { patterns: [], kidMessage: '' }, {
    patterns: [{ ...fixture.patterns[0], id: 'invented' }], kidMessage: fixture.kidMessage,
  }])('returns deterministic ranking when Claude returns no valid findings: %j', async (result) => {
    vi.mocked(claudeJson).mockResolvedValue(result);
    const response = await POST(request());
    expect(response.status).toBe(200);
    expect((await response.json()).patterns.map((pattern: { id: string }) => pattern.id)).toEqual(['ed', 'oo']);
  });

  it('skips Claude for a clean read', async () => {
    const response = await POST(request({
      ...sampleRequest,
      alignment: { ...sampleRequest.alignment, words: sampleRequest.alignment.words.map((word) => ({ ...word, status: 'correct' })) },
    }));
    expect(claudeJson).not.toHaveBeenCalled();
    expect(await response.json()).toMatchObject({ patterns: [{ id: 'ed', confidence: 0.2 }] });
  });

  it('skips Claude when miscues have no taxonomy candidates', async () => {
    const response = await POST(request({
      ...sampleRequest, pageText: 'cat',
      alignment: { words: [{ index: 0, expected: 'cat', status: 'omission' }], insertions: [] },
    }));
    expect(claudeJson).not.toHaveBeenCalled();
    expect((await response.json()).patterns).toEqual([]);
  });

  it.each([null, [], {}, { ...sampleRequest, pageText: 12 }, { ...sampleRequest, alignment: null }])
    ('keeps malformed requests from causing a 500: %j', async (body) => {
      const response = await POST(request(body));
      expect(response.status).toBe(200);
      expect((await response.json()).patterns).toEqual([]);
      expect(claudeJson).not.toHaveBeenCalled();
    });

  it('handles invalid JSON without a 500', async () => {
    const response = await POST(new Request('http://localhost/api/diagnose', { method: 'POST', body: '{' }));
    expect(response.status).toBe(200);
    expect((await response.json()).kidMessage).toMatch(/^Pip noticed/);
    expect(claudeJson).not.toHaveBeenCalled();
  });
});
