import { execFile } from "node:child_process";
import path from "node:path";
import { promisify } from "node:util";
import type { Card, CommentThread, Inbox, Kind, RecordKind, SavedView } from "./shared";

export * from "./shared";

const run = promisify(execFile);

const script =
	process.env.BOARD_CARD ??
	path.join(process.cwd(), "..", "marketplace", "plugins", "cockpit", "scripts", "board-card");

export class BoardError extends Error {}

export function commentAuthor(): string | null {
	return process.env.COCKPIT_AUTHOR || process.env.USER || null;
}

async function boardCard(args: string[], input?: string): Promise<string> {
	try {
		const pending = run(script, args, {
			env: { ...process.env, COCKPIT_AUTHOR: commentAuthor() ?? undefined },
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

export async function listRecords(kind: RecordKind, archived = false): Promise<Card[]> {
	const args = ["list", "--kind", kind, "--json"];
	if (archived) args.push("--archived");
	const records: Card[] = JSON.parse(await boardCard(args));
	return records.map((record) => ({ ...record, body: "" }));
}

export async function readRecord(id: string): Promise<Card> {
	return JSON.parse(await boardCard(["show", id, "--json"]));
}

export async function searchContent(kind: Kind, text: string): Promise<string[]> {
	return (await boardCard(["search", text, "--kind", kind])).split("\n").filter(Boolean);
}

export async function listAttachments(id: string): Promise<string[]> {
	return (await boardCard(["attachments", id])).split("\n").filter(Boolean);
}

export async function boardRevision(): Promise<string> {
	return (await boardCard(["revision"])).trim();
}

export async function readInbox(limit = 100): Promise<Inbox> {
	return JSON.parse(await boardCard(["inbox", "--json", "--limit", String(limit)]));
}

export async function meNames(): Promise<string[]> {
	const names = (await boardCard(["me"])).split("\n").filter(Boolean);
	const author = commentAuthor();
	return author && !names.includes(author) ? [...names, author] : names;
}

export async function readViews(kind: Kind): Promise<SavedView[]> {
	const views: SavedView[] = JSON.parse(await boardCard(["views", "--json"]));
	return views.filter((view) => view.kind === kind);
}

export async function saveNamedView(kind: Kind, name: string, view: Record<string, unknown>): Promise<void> {
	await boardCard(["views", "save", "--kind", kind, "--", name], JSON.stringify(view));
}

export async function deleteNamedView(kind: Kind, name: string): Promise<void> {
	await boardCard(["views", "delete", "--kind", kind, "--", name]);
}

export async function readInboxUpTo(stamp: string): Promise<void> {
	await boardCard(["inbox", "--read", stamp]);
}

export async function boardDirectory(): Promise<string> {
	return (await boardCard(["path"])).trim();
}

export async function boardTracks(value?: string): Promise<number> {
	const args = ["tracks"];
	if (value !== undefined) args.push(value);
	return Number((await boardCard(args)).trim()) || 0;
}

export async function changeStatus(record: Card, column: string): Promise<void> {
	await boardCard(["move", record.id, column]);
}

export async function moveRecords(ids: string[], column: string): Promise<string[]> {
	const output = await boardCard(["move", ...ids, column]);
	return [...output.matchAll(/^(\S+)\t/gm)].map((match) => match[1]);
}

export async function setField(id: string, field: string, value: string): Promise<string> {
	return (await setFieldHolding(id, field, value)).id;
}

export async function setFieldHolding(
	id: string,
	field: string,
	value: string,
): Promise<{ id: string; held: string[] }> {
	const output = await boardCard(["set", id, field, value]);
	const current = output.match(/^renamed \S+ to (\S+)$/m)?.[1] ?? id;
	const held = [...output.matchAll(/^(\S+)\tdue /gm)].map((match) => match[1]).filter((card) => card !== current);
	return { id: current, held };
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

export type CreateOptions = {
	type?: string;
	epic?: string;
	project?: string;
	body?: string;
	fields?: Record<string, string>;
};

export async function createRecord(
	kind: RecordKind,
	name: string,
	status: string,
	options: CreateOptions = {},
): Promise<string> {
	const args = ["create", "--kind", kind, "--name", name];
	if (status) args.push("--status", status);
	if (kind === "card" && options.type) args.push("--type", options.type);
	if (kind === "card" && options.epic) args.push("--epic", options.epic);
	if ((kind === "card" || kind === "epic") && options.project) args.push("--project", options.project);
	for (const [field, value] of Object.entries(options.fields ?? {})) {
		if (value) args.push(`--${field.replace(/_/g, "-")}`, value);
	}
	if (options.body) args.push("--body", "-");
	return (await boardCard(args, options.body)).trim().split("\n").at(-1) ?? "";
}

export async function duplicateRecord(id: string, status?: string): Promise<string> {
	const args = ["duplicate", id];
	if (status) args.push("--status", status);
	return (await boardCard(args)).trim().split("\n").at(-1) ?? "";
}

export async function archiveRecord(id: string): Promise<void> {
	await boardCard(["archive", id]);
}

export async function unarchiveRecord(id: string): Promise<void> {
	await boardCard(["unarchive", id]);
}

export async function isArchived(id: string): Promise<boolean> {
	try {
		const [file, directory] = await Promise.all([boardCard(["path", id]), boardDirectory()]);
		return file.trim().startsWith(`${directory}/archive/`);
	} catch (error) {
		if (error instanceof BoardError) return false;
		throw error;
	}
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

export async function commitsOf(id: string): Promise<string[]> {
	try {
		return (await boardCard(["history", id]))
			.split("\n")
			.filter(Boolean)
			.map((line) => line.split("\t")[0]);
	} catch (error) {
		if (error instanceof BoardError) return [];
		throw error;
	}
}

export async function undoSince(id: string, since: string, until: string): Promise<string> {
	const output = await boardCard(["undo", id, "--since", since, "--until", until]);
	return output.split("\t")[0] || id;
}

export async function readComments(id: string): Promise<CommentThread[]> {
	return JSON.parse(await boardCard(["comments", id, "--all", "--json"]));
}

export async function addComment(id: string, text: string, anchor?: string, reply?: string): Promise<void> {
	const args = ["comment", id];
	if (anchor) args.push("--anchor", anchor);
	if (reply) args.push("--reply", reply);
	await boardCard(args, text);
}

export async function resolveComment(id: string, thread: string, resolved = true): Promise<void> {
	await boardCard([resolved ? "resolve" : "reopen", id, thread]);
}

export async function editComment(id: string, comment: string, text: string): Promise<void> {
	await boardCard(["comment", id, "--edit", comment], text);
}

export async function deleteComment(id: string, comment: string): Promise<void> {
	await boardCard(["uncomment", id, comment]);
}
