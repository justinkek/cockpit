import { readFile } from "node:fs/promises";
import path from "node:path";
import { BoardError, boardDirectory } from "@/lib/board";
import { type HeldBatch, heldBatches } from "@/lib/held";

export const dynamic = "force-dynamic";

let directory: Promise<string> | null = null;

function board() {
	directory ??= boardDirectory().catch((error) => {
		directory = null;
		throw error;
	});
	return directory;
}

function delay() {
	const seconds = Number(process.env.COCKPIT_COMMIT_DELAY ?? 3);
	return Number.isFinite(seconds) && seconds >= 0 ? seconds : 3;
}

export async function GET() {
	const headers = { "Cache-Control": "no-store" };
	try {
		const file = path.join(await board(), ".git", "board-card-held");
		const text = await readFile(file, "utf8").catch(() => "");
		const batches: HeldBatch[] = heldBatches(text, delay());
		return Response.json({ batches, now: Date.now() }, { headers });
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return Response.json({ error: error.message }, { status: 503, headers });
	}
}
