import { execFile } from "node:child_process";
import path from "node:path";
import { promisify } from "node:util";
import { type Card, type CommentThread, type Kind, kindOf, walkColumns } from "./shared";

export * from "./shared";

const run = promisify(execFile);

const script =
	process.env.BOARD_CARD ??
	path.join(process.cwd(), "..", "marketplace", "plugins", "cockpit", "scripts", "board-card");

export class BoardError extends Error {}

async function boardCard(args: string[], input?: string): Promise<string> {
	try {
		const pending = run(script, args, {
			env: { ...process.env, COCKPIT_AUTHOR: process.env.COCKPIT_AUTHOR ?? process.env.USER },
			maxBuffer: 256 * 1024 * 1024,
		});
		pending.child.stdin?.end(input ?? "");
		const { stdout } = await pending;
		return stdout;
	} catch (error) {
		const stderr = (error as { stderr?: string }).stderr?.trim();
		throw new BoardError(stderr?.replace(/^\[board-card\] /, "") || String(error));
	}
}

export async function listRecords(kind: Kind | "project" | "sprint"): Promise<Card[]> {
	const records: Card[] = JSON.parse(await boardCard(["list", "--kind", kind, "--json"]));
	return records.map((record) => ({ ...record, body: "" }));
}

export async function readRecord(id: string): Promise<Card> {
	return JSON.parse(await boardCard(["show", id, "--json"]));
}

export async function boardDirectory(): Promise<string> {
	return (await boardCard(["path"])).trim();
}

export async function changeStatus(record: Card, column: string): Promise<void> {
	const columns = walkColumns(kindOf(record.id) ?? "card");
	const from = columns.indexOf(record.status);
	const to = columns.indexOf(column);
	const forward = from >= 0 && to > from;
	await boardCard([forward ? "walk" : "move", record.id, column]);
}

export async function setField(id: string, field: string, value: string): Promise<string> {
	const output = await boardCard(["set", id, field, value]);
	return output.match(/^renamed \S+ to (\S+)$/m)?.[1] ?? id;
}

export async function findRenamed(id: string): Promise<string | null> {
	const match = id.toUpperCase().match(/^(?:FEAT|BUG|TIME)-(\d+)$/);
	if (!match) return null;
	for (const prefix of ["FEAT", "BUG", "TIME"]) {
		const alias = `${prefix}-${match[1]}`;
		if (alias === id.toUpperCase()) continue;
		try {
			return (await readRecord(alias)).id;
		} catch (error) {
			if (!(error instanceof BoardError)) throw error;
		}
	}
	return null;
}

export async function link(parent: string, child: string, linked: boolean): Promise<void> {
	await boardCard([linked ? "link" : "unlink", parent, child]);
}

export async function lastCommit(id: string): Promise<string | null> {
	try {
		return (await boardCard(["history", id])).split("\t")[0] || null;
	} catch (error) {
		if (error instanceof BoardError) return null;
		throw error;
	}
}

export async function undoSince(id: string, commit: string): Promise<string> {
	const output = await boardCard(["undo", id, "--since", commit]);
	return output.split("\t")[0] || id;
}

export async function readComments(id: string): Promise<CommentThread[]> {
	return JSON.parse(await boardCard(["comments", id, "--json"]));
}

export async function addComment(id: string, text: string, anchor?: string, reply?: string): Promise<void> {
	const args = ["comment", id];
	if (anchor) args.push("--anchor", anchor);
	if (reply) args.push("--reply", reply);
	await boardCard(args, text);
}

export async function resolveComment(id: string, thread: string): Promise<void> {
	await boardCard(["resolve", id, thread]);
}
