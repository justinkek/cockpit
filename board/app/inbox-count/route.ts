import { BoardError, readInbox } from "@/lib/board";

export const dynamic = "force-dynamic";

export async function GET() {
	try {
		const inbox = await readInbox(20);
		return Response.json(
			{ unread: inbox.unread, items: inbox.items.filter((item) => item.unread) },
			{ headers: { "Cache-Control": "no-store" } },
		);
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return Response.json({ error: error.message }, { status: 503, headers: { "Cache-Control": "no-store" } });
	}
}
