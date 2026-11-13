import { isMockRequest } from '@/lib/mock';
import { createPracticeBook, fallbackPracticeBook, requestPattern } from './practice-book';

export async function POST(req: Request) {
  const pattern = requestPattern(await req.json().catch(() => null));
  try {
    return Response.json(await createPracticeBook(pattern, isMockRequest(req)));
  } catch {
    return Response.json(fallbackPracticeBook(pattern));
  }
}
