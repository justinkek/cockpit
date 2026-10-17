"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import {
	addBreak,
	addComment,
	archiveEntity,
	BoardError,
	type Break,
	boardTracks,
	type Card,
	type CommentThread,
	type HistoryEntry,
	type Kind,
	kindName,
	changeStatus,
	closeProjectEntity,
	commentAuthor,
	commitsOf,
	createEntity,
	deleteComment,
	deleteNamedView,
	editComment,
	duplicateEntity,
	findRenamed,
	lastCommit,
	link,
	listEntities,
	mergeBody,
	moveEntities,
	readComments,
	readHistory,
	readInboxUpTo,
	readBreaks,
	readEntity,
	readViews,
	removeBreak,
	type SavedView,
	saveNamedView,
	resolveComment,
	searchContent,
	setField,
	setFieldHolding,
	unarchiveEntity,
	undoSince,
} from "@/lib/board";
import { lookupEntity, type EntityLookup } from "@/lib/entity-view";

type Failure = { error?: string; moved?: string; archived?: boolean };
export type Span = { since: string; until: string };
export type Change = { id: string } & Span;
type Result = Failure & { entity?: Card; undo?: Span; more?: Change[] };
type Threads = Failure & { threads?: CommentThread[]; me?: string | null };
export type NewOptions = {
	type?: string;
	epic?: string;
	rank?: number;
	body?: string;
	project?: string;
	timeboxMins?: string;
	icon?: string;
	urgent?: boolean;
};

function refresh(id: string) {
	revalidatePath("/");
	revalidatePath("/epics");
	revalidatePath("/projects");
	revalidatePath("/obeya");
	revalidatePath("/references");
	revalidatePath("/archive");
	revalidatePath("/plan");
	revalidatePath(`/card/${id}`);
}

async function heldChanges(held: string[], until: string | undefined): Promise<Change[]> {
	if (!until || held.length === 0) return [];
	const changes: Change[] = [];
	for (const card of [...new Set(held)]) {
		const [last, before] = await commitsOf(card);
		if (last === until && before) changes.push({ id: card, since: before, until });
		refresh(card);
	}
	return changes;
}

async function failed(id: string, error: unknown): Promise<Failure> {
	if (!(error instanceof BoardError)) throw error;
	const archived = error.message.match(/^(\S+) is archived - run: /)?.[1];
	if (archived === id) {
		return {
			error: `${id} was archived elsewhere, so this change was not saved - bring it back to change it`,
			archived: true,
		};
	}
	if (archived) return { error: `${archived} is archived - bring it back from its page first` };
	const missing = error.message.match(/^no entity (\S+) in /)?.[1];
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
		return {
			entity: await readEntity(current),
			undo: since && after && after !== since ? { since, until: after } : undefined,
		};
	} catch (error) {
		return failed(id, error);
	}
}

export async function undoChange(id: string, span: Span): Promise<Result> {
	try {
		const current = await undoSince(id, span.since, span.until);
		refresh(id);
		refresh(current);
		return { entity: await readEntity(current) };
	} catch (error) {
		return failed(id, error);
	}
}

export async function loadHistory(id: string): Promise<Failure & { entries?: HistoryEntry[] }> {
	try {
		return { entries: await readHistory(id) };
	} catch (error) {
		return failed(id, error);
	}
}

export async function restoreVersion(id: string, commit: string): Promise<Result> {
	try {
		const since = await lastCommit(id);
		if (!since) return { error: `${id} has no history to restore from` };
		const current = await undoSince(id, commit, since);
		refresh(id);
		refresh(current);
		const after = await lastCommit(current);
		return {
			entity: await readEntity(current),
			undo: after && after !== since ? { since, until: after } : undefined,
		};
	} catch (error) {
		return failed(id, error);
	}
}

async function threadsAfter(id: string, change: () => Promise<void>): Promise<Threads> {
	try {
		await change();
		refresh(id);
		return { threads: await readComments(id), me: commentAuthor() };
	} catch (error) {
		return failed(id, error);
	}
}

function rankText(rank: number) {
	return rank.toFixed(6).replace(/\.?0+$/, "");
}

export type FieldSet = { field: string; value: string };

export async function dropCard(id: string, column: string, rank?: number, sets: FieldSet[] = []): Promise<Result> {
	const held: string[] = [];
	const result = await report(id, async () => {
		let current = id;
		for (const { field, value } of sets) {
			const change = await setFieldHolding(current, field, value);
			held.push(...change.held);
			current = change.id;
		}
		const entity = await readEntity(current);
		if (entity.status !== column) await changeStatus(entity, column);
		if (rank !== undefined) await setField(current, "rank", rankText(rank));
		return current;
	});
	return { ...result, more: await heldChanges(held, result.undo?.until) };
}

export async function createCard(kind: Kind, name: string, status: string, options: NewOptions = {}): Promise<Result> {
	const typed = name.replace(/\s*[\r\n]+\s*/g, " ").trim();
	if (!typed) return { error: `a new ${kindName(kind)} needs a name` };
	let id = "";
	try {
		id = await createEntity(kind, typed, status, {
			...options,
			fields: {
				...(kind === "card" && options.timeboxMins ? { timebox_mins: options.timeboxMins } : {}),
				...(options.icon ? { icon: options.icon } : {}),
			},
		});
		if (options.rank !== undefined) await setField(id, "rank", rankText(options.rank));
		if (kind === "card" && options.urgent) await setField(id, "urgent", "true");
		refresh(id);
		return { entity: await readEntity(id) };
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return { error: id ? `${id} was created, but ${error.message}` : error.message, moved: id || undefined };
	}
}

export async function duplicateCard(id: string): Promise<Result> {
	try {
		const source = await readEntity(id);
		const copy = await duplicateEntity(id, source.status);
		refresh(copy);
		return { entity: await readEntity(copy) };
	} catch (error) {
		return failed(id, error);
	}
}

export async function archiveOne(id: string): Promise<Failure> {
	try {
		await archiveEntity(id);
		refresh(id);
		return {};
	} catch (error) {
		return failed(id, error);
	}
}

export async function submitUnarchive(form: FormData): Promise<void> {
	const id = text(form, "id");
	const back = text(form, "back") === "archive" ? "/archive" : `/card/${encodeURIComponent(id)}`;
	let failure = "";
	try {
		await unarchiveEntity(id);
		refresh(id);
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		failure = `Could not bring ${id} back: ${error.message}`;
	}
	if (failure) redirect(`${back}?error=${encodeURIComponent(failure)}`);
	redirect(back === "/archive" ? `/archive?restored=${encodeURIComponent(id)}` : back);
}

export async function submitNew(form: FormData): Promise<void> {
	const kind: Kind = text(form, "kind") === "epic" ? "epic" : "card";
	const result = await createCard(kind, text(form, "name"), text(form, "status"), {
		type: text(form, "type") || undefined,
		epic: text(form, "epic") || undefined,
		project: text(form, "project") || undefined,
		timeboxMins: text(form, "timebox_mins") || undefined,
		icon: text(form, "icon") || undefined,
		body: typeof form.get("body") === "string" ? String(form.get("body")).replace(/\r\n/g, "\n") : undefined,
	});
	const made = result.entity?.id ?? result.moved;
	if (made)
		redirect(`/card/${encodeURIComponent(made)}${result.error ? `?error=${encodeURIComponent(result.error)}` : ""}`);
	redirect(
		`${kind === "epic" ? "/epics" : "/"}?error=${encodeURIComponent(`Could not create the ${kindName(kind)}: ${result.error}`)}`,
	);
}

const CREATED_WITH = ["icon", "start", "end", "dev_days", "speed", "priority", "repo", "key"];

const SET_AFTER = ["points", "domain", "stack", "why", "description", "card"];

export async function submitEntity(_previous: string | null, form: FormData): Promise<string | null> {
	const kind = text(form, "kind");
	if (!(kind === "project" || kind === "sprint" || kind === "reference")) redirect("/");
	const name = text(form, "name").replace(/\s*[\r\n]+\s*/g, " ");
	const refused = (error: string) => `Could not create the ${kind}: ${error}`;
	if (!name) return refused(`a new ${kind} needs a name`);
	const fields = Object.fromEntries(
		CREATED_WITH.map((field) => [field, text(form, field)]).filter(([, value]) => value),
	);
	let id = "";
	let failure = "";
	try {
		id = await createEntity(kind, name, text(form, "status"), { fields });
		for (const field of SET_AFTER) {
			const value = text(form, field);
			if (value) await setField(id, field, value);
		}
		refresh(id);
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		failure = id ? `${id} was created, but ${error.message}` : error.message;
	}
	if (!id) return refused(failure);
	const query = failure ? `error=${encodeURIComponent(failure)}` : "";
	if (kind === "sprint") redirect(`/obeya?sprint=${encodeURIComponent(id)}${query ? `&${query}` : ""}#sprint`);
	redirect(`/card/${encodeURIComponent(id)}${query ? `?${query}` : ""}`);
}

export async function editCard(id: string, field: string, value: string): Promise<Result> {
	const held: string[] = [];
	const result = await report(id, async () => {
		const change = await setFieldHolding(id, field, value);
		held.push(...change.held);
		return change.id;
	});
	return { ...result, more: await heldChanges(held, result.undo?.until) };
}

export async function closeProject(id: string): Promise<Result & { closed?: Change[] }> {
	const moved: string[] = [];
	const result = await report(id, async () => {
		moved.push(...(await closeProjectEntity(id)));
	});
	return { ...result, closed: await heldChanges(moved, result.undo?.until) };
}

export type Ranked = { id: string; rank: number };

export async function rankPlan(order: Ranked[]): Promise<BulkResult> {
	const result: BulkResult = { entities: [], undo: [], errors: [] };
	for (const { id, rank } of order) {
		const changed = await report(id, () => setField(id, "rank", rankText(rank)));
		if (changed.error) result.errors.push(`${id}: ${changed.error}`);
		if (changed.entity) result.entities.push({ from: id, entity: changed.entity });
		if (changed.undo) result.undo.push({ id, ...changed.undo });
	}
	return result;
}

async function deprioritiseOpen(cards: string[], result: BulkResult): Promise<boolean> {
	if (cards.length === 0) return true;
	try {
		const moved = await moveEntities(cards, "Deprioritised");
		const until = moved.length > 0 ? await lastCommit(moved[0]) : null;
		for (const card of moved) {
			refresh(card);
			if (until) result.undo.push({ id: card, since: `${until}^`, until });
		}
		return true;
	} catch (error) {
		const failure = await failed(cards[0], error);
		result.errors.push(failure.error ?? "the open tickets could not be deprioritised");
		return false;
	}
}

export async function finishEpic(id: string, cards: string[]): Promise<BulkResult & { entity?: Card }> {
	const result: BulkResult = { entities: [], undo: [], errors: [] };
	if (!(await deprioritiseOpen(cards, result))) return result;
	const moved = await dropCard(id, "Epic Done");
	if (moved.error) return { ...result, errors: [`${id}: ${moved.error}`] };
	if (moved.undo) result.undo.push({ id, ...moved.undo });
	return { ...result, entity: moved.entity };
}

export async function finishEpics(ids: string[], cards: string[]): Promise<BulkResult> {
	const result: BulkResult = { entities: [], undo: [], errors: [] };
	if (!(await deprioritiseOpen(cards, result))) return result;
	const epics = await bulkChange(ids, { op: "move", column: "Epic Done" });
	return { entities: epics.entities, undo: [...result.undo, ...epics.undo], errors: epics.errors };
}

export async function setBoardTracks(count: number): Promise<{ tracks?: number; error?: string }> {
	try {
		const tracks = await boardTracks(String(count));
		revalidatePath("/plan");
		return { tracks };
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return { error: error.message };
	}
}

export async function saveBreak(
	from: string,
	to: string,
	name: string,
	id?: string,
): Promise<{ breaks?: Break[]; id?: string; error?: string }> {
	try {
		const added = await addBreak(from, to, name.replace(/\s*[\r\n]+\s*/g, " ").trim(), id);
		revalidatePath("/plan");
		return { breaks: await readBreaks(), id: added };
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return { error: error.message };
	}
}

export async function dropBreak(id: string): Promise<{ breaks?: Break[]; error?: string }> {
	try {
		await removeBreak(id);
		revalidatePath("/plan");
		return { breaks: await readBreaks() };
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return { error: error.message };
	}
}

export async function createMilestone(name: string, date: string): Promise<Result> {
	const typed = name.replace(/\s*[\r\n]+\s*/g, " ").trim();
	if (!typed) return { error: "a milestone needs a name" };
	try {
		const id = await createEntity("milestone", typed, "", { fields: { date } });
		refresh(id);
		return { entity: await readEntity(id) };
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return { error: error.message };
	}
}

export async function removeMilestone(id: string): Promise<Failure & { undo?: Span }> {
	try {
		const since = await lastCommit(id);
		await archiveEntity(id);
		refresh(id);
		const until = await lastCommit(id);
		return { undo: since && until && until !== since ? { since, until } : undefined };
	} catch (error) {
		return failed(id, error);
	}
}

export async function linkCards(id: string, parent: string, child: string, linked: boolean): Promise<Result> {
	return report(id, async () => {
		const other = parent === id ? child : parent;
		await link(parent, child, linked);
		refresh(other);
	});
}

export async function saveBody(id: string, base: string, text: string): Promise<Result & { conflicts?: number }> {
	let conflicts = 0;
	const result = await report(id, async () => {
		conflicts = (await mergeBody(id, base, text)).conflicts;
	});
	return conflicts > 0 ? { ...result, conflicts } : result;
}

export async function loadBody(id: string): Promise<Failure & { body?: string }> {
	try {
		return { body: (await readEntity(id)).body };
	} catch (error) {
		return failed(id, error);
	}
}

export async function findInContent(kind: Kind, query: string): Promise<{ ids: string[] } | { error: string }> {
	try {
		return { ids: await searchContent(kind, query) };
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return { error: error.message };
	}
}

export async function loadComments(id: string): Promise<Threads> {
	try {
		return { threads: await readComments(id), me: commentAuthor() };
	} catch (error) {
		return failed(id, error);
	}
}

export async function postComment(id: string, text: string, anchor?: string, reply?: string): Promise<Threads> {
	return threadsAfter(id, () => addComment(id, text, anchor, reply));
}

export async function resolveThread(id: string, thread: string, resolved = true): Promise<Threads> {
	return threadsAfter(id, () => resolveComment(id, thread, resolved));
}

export async function changeComment(id: string, comment: string, text: string): Promise<Threads> {
	return threadsAfter(id, () => editComment(id, comment, text));
}

export async function removeComment(id: string, comment: string): Promise<Threads> {
	return threadsAfter(id, () => deleteComment(id, comment));
}

export async function storeView(
	kind: Kind,
	name: string,
	view: Record<string, unknown>,
): Promise<{ views?: SavedView[]; error?: string }> {
	const typed = name.replace(/\s*[\r\n]+\s*/g, " ").trim();
	if (!typed) return { error: "a saved view needs a name" };
	try {
		await saveNamedView(kind, typed, view);
		return { views: await readViews(kind) };
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return { error: error.message };
	}
}

export async function forgetView(kind: Kind, name: string): Promise<{ views?: SavedView[]; error?: string }> {
	try {
		await deleteNamedView(kind, name);
		return { views: await readViews(kind) };
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return { error: error.message };
	}
}

export async function markInboxRead(stamp: string): Promise<Failure> {
	try {
		await readInboxUpTo(stamp);
		revalidatePath("/inbox");
		return {};
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return { error: error.message };
	}
}

function text(form: FormData, name: string) {
	const value = form.get(name);
	return typeof value === "string" ? value.trim() : "";
}

async function cardNamed(typed: string): Promise<string> {
	const id = typed.match(/^([A-Za-z]+-\d+)\b/)?.[1]?.toUpperCase();
	if (id) return id;
	const named = (await listEntities("card")).find((card) => card.name.toLowerCase() === typed.toLowerCase());
	if (!named) throw new BoardError(`no ticket called '${typed}'`);
	return named.id;
}

export async function submitCard(form: FormData): Promise<void> {
	const id = text(form, "id");
	let current = id;
	let failure = "";
	try {
		const field = text(form, "field");
		const raw = form.get("value");
		const value =
			field === "name"
				? text(form, "value").replace(/\s*[\r\n]+\s*/g, " ")
				: field === "body" && typeof raw === "string"
					? raw.replace(/\r\n/g, "\n")
					: text(form, "value");
		switch (text(form, "op")) {
			case "move":
				await changeStatus(await readEntity(id), value);
				break;
			case "set":
				if (field === "body" && typeof form.get("base") === "string")
					await mergeBody(id, String(form.get("base")).replace(/\r\n/g, "\n"), value);
				else current = await setField(id, field, value);
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

export type Bulk = { op: "move"; column: string } | { op: "set"; field: string; value: string } | { op: "archive" };

export type BulkResult = {
	entities: { from: string; entity: Card | null }[];
	undo: ({ id: string } & Span)[];
	errors: string[];
};

export async function bulkChange(ids: string[], change: Bulk): Promise<BulkResult> {
	const result: BulkResult = { entities: [], undo: [], errors: [] };
	for (const id of ids) {
		try {
			const since = await lastCommit(id);
			let current = id;
			if (change.op === "move") {
				const entity = await readEntity(id);
				if (entity.status !== change.column) await changeStatus(entity, change.column);
			} else if (change.op === "set") {
				current = await setField(id, change.field, change.value);
			} else {
				await archiveEntity(id);
			}
			refresh(current);
			const after = since ? await lastCommit(current) : null;
			if (since && after && after !== since) result.undo.push({ id: current, since, until: after });
			result.entities.push({ from: id, entity: change.op === "archive" ? null : await readEntity(current) });
		} catch (error) {
			const failure = await failed(id, error);
			result.errors.push(`${id}: ${failure.error ?? "failed"}`);
		}
	}
	return result;
}

export async function loadEntityView(id: string): Promise<EntityLookup> {
	return lookupEntity(id);
}
