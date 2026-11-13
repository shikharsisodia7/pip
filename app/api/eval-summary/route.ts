import fs from 'node:fs/promises';
import path from 'node:path';
import { extractSummary } from './summary';

// GET /api/eval-summary
// Returns the eval's one-line summary when eval/results.json exists, else
// { summary: null }. Never fails: the report simply hides the footer.
export async function GET() {
  try {
    const raw = await fs.readFile(path.join(process.cwd(), 'eval', 'results.json'), 'utf8');
    return Response.json({ summary: extractSummary(JSON.parse(raw)) });
  } catch {
    return Response.json({ summary: null });
  }
}
