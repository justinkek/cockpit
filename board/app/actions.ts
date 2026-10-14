"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import {
	addComment,
	BoardError,
	type Card,
	type CommentThread,
	type Kind,
	changeStatus,
	createRecord,
	findRenamed,
	lastCommit,
	link,
	listRecords,
	readComments,
	readRecord,
	resolveComment,
	setField,
	undoSince,
} from "@/lib/board";

type Failure = { error?: string; moved?: string };
type Result = Failure & { record?: Card; undo?: string };
type Threads = Failure & { threads?: CommentThread[] };

function refresh(id: string) {
	revalidatePath("/");
	revalidatePath("/epics");
	revalidatePath(`/card/${id}`);
}

async function failed(id: string, error: unknown): Promise<Failure> {
	if (!(error instanceof BoardError)) throw error;
	const missing = error.message.match(/^no record (\S+) in /)?.[1];
	if (!missing) return { error: error.message };
	if (missing !== id) return { error: `${missing} is not on the board` };
	const moved = await findRenamed(id);
	if (moved) return { error: `${id} is now ${moved} - it was changed elsewhere, so this change was not saved`, moved };
	return { error: `${id} is no longer on the board - reload to see what changed` };
}

async function report(id: string, change: () => Promise<string | void>): Promise<Result> {
	try {
		const since = await lastCommit(id);
		const current = (await change()) || id;
		refresh(current);
		const after = since ? await lastCommit(current) : null;
		return { record: await readRecord(current), undo: since && after && after !== since ? since : undefined };
	} catch (error) {
		return failed(id, error);
	}
}

export async function undoChange(id: string, since: string): Promise<Result> {
	try {
		const current = await undoSince(id, since);
		refresh(id);
		refresh(current);
		return { record: await readRecord(current) };
	} catch (error) {
		return failed(id, error);
	}
}

async function threadsAfter(id: string, change: () => Promise<void>): Promise<Threads> {
	try {
		await change();
		refresh(id);
		return { threads: await readComments(id) };
	} catch (error) {
		return failed(id, error);
	}
}

function rankText(rank: number) {
	return rank.toFixed(6).replace(/\.?0+$/, "");
}

export async function dropCard(id: string, column: string, rank?: number): Promise<Result> {
	return report(id, async () => {
		const record = await readRecord(id);
		if (record.status !== column) await changeStatus(record, column);
		if (rank !== undefined) await setField(id, "rank", rankText(rank));
	});
}

export async function createCard(
	kind: Kind,
	name: string,
	status: string,
	options: { type?: string; epic?: string; rank?: number } = {},
): Promise<Result> {
	const typed = name.replace(/\s*[\r\n]+\s*/g, " ").trim();
	if (!typed) return { error: "a new card needs a name" };
	try {
		const id = await createRecord(kind, typed, status, options);
		if (options.rank !== undefined) await setField(id, "rank", rankText(options.rank));
		refresh(id);
		return { record: await readRecord(id) };
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return { error: error.message };
	}
}

export async function editCard(id: string, field: string, value: string): Promise<Result> {
	return report(id, () => setField(id, field, value));
}

export async function linkCards(id: string, parent: string, child: string, linked: boolean): Promise<Result> {
	return report(id, async () => {
		const other = parent === id ? child : parent;
		await link(parent, child, linked);
		refresh(other);
	});
}

const TODO = /- \[( |x)\] /;

export async function checkTodo(id: string, line: number, expected: string, done: boolean): Promise<Result> {
	return report(id, async () => {
		const lines = (await readRecord(id)).body.split("\n");
		if (lines[line] !== expected || !TODO.test(expected)) {
			throw new BoardError("that to-do has changed since the page loaded - reload to see it");
		}
		lines[line] = expected.replace(TODO, done ? "- [x] " : "- [ ] ");
		return setField(id, "body", lines.join("\n"));
	});
}

export async function loadBody(id: string): Promise<Failure & { body?: string }> {
	try {
		return { body: (await readRecord(id)).body };
	} catch (error) {
		return failed(id, error);
	}
}

export async function loadComments(id: string): Promise<Threads> {
	try {
		return { threads: await readComments(id) };
	} catch (error) {
		return failed(id, error);
	}
}

export async function postComment(id: string, text: string, anchor?: string, reply?: string): Promise<Threads> {
	return threadsAfter(id, () => addComment(id, text, anchor, reply));
}

export async function resolveThread(id: string, thread: string): Promise<Threads> {
	return threadsAfter(id, () => resolveComment(id, thread));
}

function text(form: FormData, name: string) {
	const value = form.get(name);
	return typeof value === "string" ? value.trim() : "";
}

async function cardNamed(typed: string): Promise<string> {
	const id = typed.match(/^([A-Za-z]+-\d+)\b/)?.[1]?.toUpperCase();
	if (id) return id;
	const named = (await listRecords("card")).find((card) => card.name.toLowerCase() === typed.toLowerCase());
	if (!named) throw new BoardError(`no card called '${typed}'`);
	return named.id;
}

export async function submitCard(form: FormData): Promise<void> {
	const id = text(form, "id");
	let current = id;
	let failure = "";
	try {
		const field = text(form, "field");
		const value = field === "name" ? text(form, "value").replace(/\s*[\r\n]+\s*/g, " ") : text(form, "value");
		switch (text(form, "op")) {
			case "move":
				await changeStatus(await readRecord(id), value);
				break;
			case "set":
				current = await setField(id, field, value);
				break;
			case "link": {
				const other = await cardNamed(value);
				if (text(form, "side") === "parent") await link(other, id, true);
				else await link(id, other, true);
				refresh(other);
				break;
			}
			case "unlink":
				await link(text(form, "parent"), text(form, "child"), false);
				break;
			default:
				throw new BoardError("that form sent no change");
		}
		refresh(current);
	} catch (error) {
		const result = await failed(current, error);
		failure = result.error ?? "";
		current = result.moved ?? current;
	}
	redirect(`/card/${encodeURIComponent(current)}${failure ? `?error=${encodeURIComponent(failure)}` : ""}`);
}
