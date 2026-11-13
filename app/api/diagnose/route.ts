import { isMockRequest } from '@/lib/mock';
import { claudeJson } from '@/lib/server/claudeJson';
import type { DiagnoseResponse } from '@/lib/types';
import {
  buildDiagnosisContext,
  diagnoseRequestSchema,
  diagnoseResponseSchema,
  diagnoseSystem,
  fallbackDiagnosis,
  validateDiagnosis,
} from './diagnose';

export async function POST(req: Request) {
  const parsed = diagnoseRequestSchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return Response.json({
      patterns: [],
      kidMessage: "Pip noticed there's more to explore. Let's read together!",
    } satisfies DiagnoseResponse);
  }

  const { pageText, alignment } = parsed.data;
  const context = buildDiagnosisContext(pageText, alignment);
  const fallback = fallbackDiagnosis(pageText, context);
  if (!context.miscues.length || !context.candidates.length) return Response.json(fallback);

  try {
    const result = await claudeJson<DiagnoseResponse>({
      name: 'diagnose',
      fixture: 'fixtures/claude/diagnose-demo.json',
      mock: isMockRequest(req),
      schema: diagnoseResponseSchema,
      system: diagnoseSystem,
      prompt: JSON.stringify({ pageText, ...context }),
    });
    return Response.json(validateDiagnosis(result, context) ?? fallback);
  } catch {
    return Response.json(fallback);
  }
}
