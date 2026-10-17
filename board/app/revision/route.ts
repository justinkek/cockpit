import { BoardError, boardRevision } from "@/lib/board";

export const dynamic = "force-dynamic";

export async function GET() {
	try {
		return Response.json({ revision: await boardRevision() }, { headers: { "Cache-Control": "no-store" } });
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return Response.json({ error: error.message }, { status: 503, headers: { "Cache-Control": "no-store" } });
	}
}
