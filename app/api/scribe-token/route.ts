// Placeholder. The live route mints a single-use realtime Scribe token server side.
export async function GET() {
  return Response.json({ token: '' }, { status: 501 });
}
