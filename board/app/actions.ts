"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import {
	addComment,
	BoardError,
	type Card,
	type CommentThread,
	changeStatus,
	link,
	readComments,
	readRecord,
	resolveComment,
	setField,
} from "@/lib/board";

type Result = { record?: Card; error?: string };
type Threads = { threads?: CommentThread[]; error?: string };

function refresh(id: string) {
	revalidatePath("/");
	revalidatePath("/epics");
	revalidatePath(`/card/${id}`);
}

async function attempt(id: string, change: () => Promise<void>): Promise<never> {
	let failure = "";
	try {
		await change();
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		failure = error.message;
	}
	refresh(id);
	redirect(failure ? `/card/${id}?error=${encodeURIComponent(failure)}` : `/card/${id}`);
}

async function report(id: string, change: () => Promise<void>): Promise<Result> {
	try {
		await change();
		refresh(id);
		return { record: await readRecord(id) };
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return { error: error.message };
	}
}

async function threadsAfter(id: string, change: () => Promise<void>): Promise<Threads> {
	try {
		await change();
		refresh(id);
		return { threads: await readComments(id) };
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return { error: error.message };
	}
}

export async function moveCard(formData: FormData) {
	const id = String(formData.get("id"));
	const column = String(formData.get("status"));
	await attempt(id, async () => changeStatus(await readRecord(id), column));
}

export async function updateField(formData: FormData) {
	const id = String(formData.get("id"));
	const field = String(formData.get("field"));
	const value = String(formData.get("value") ?? "");
	await attempt(id, () => setField(id, field, value));
}

export async function linkChild(formData: FormData) {
	const id = String(formData.get("id"));
	const child = String(formData.get("child")).trim();
	await attempt(id, () => link(id, child, true));
}

export async function unlinkChild(formData: FormData) {
	const id = String(formData.get("id"));
	const child = String(formData.get("child"));
	await attempt(id, () => link(id, child, false));
}

export async function dropCard(id: string, column: string, rank?: number): Promise<Result> {
	return report(id, async () => {
		const record = await readRecord(id);
		if (record.status !== column) await changeStatus(record, column);
		if (rank !== undefined) await setField(id, "rank", rank.toFixed(6).replace(/\.?0+$/, ""));
	});
}

export async function editCard(id: string, field: string, value: string): Promise<Result> {
	return report(id, () => setField(id, field, value));
}

export async function loadBody(id: string): Promise<{ body?: string; error?: string }> {
	try {
		return { body: (await readRecord(id)).body };
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return { error: error.message };
	}
}

export async function loadComments(id: string): Promise<Threads> {
	try {
		return { threads: await readComments(id) };
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return { error: error.message };
	}
}

export async function postComment(id: string, text: string, anchor?: string, reply?: string): Promise<Threads> {
	return threadsAfter(id, () => addComment(id, text, anchor, reply));
}

export async function resolveThread(id: string, thread: string): Promise<Threads> {
	return threadsAfter(id, () => resolveComment(id, thread));
}
