import { getDemoBook } from '@/lib/books';

export function GET() {
  return Response.json(getDemoBook());
}
