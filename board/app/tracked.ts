"use client";

import * as raw from "@/app/actions";
import type { Bulk, BulkResult, Change, FieldSet, NewOptions, Ranked, Span } from "@/app/actions";
import { busyWith, type Outcome, type Progress, stillSaving, track } from "@/app/work";
import { entityKindOf, fieldName, type Kind, kindName } from "@/lib/shared";

const CHUNK = 10;

type Single = { error?: string; undo?: Span; more?: Change[]; entity?: { id: string } };

function many(ids: string[]) {
	if (ids.length === 1) return ids[0];
	const kind = entityKindOf(ids[0] ?? "");
	const noun = kind ? kindName(kind) : "entity";
	return `${ids.length} ${noun === "entity" ? "entities" : `${noun}s`}`;
}

function single(result: Single & { closed?: Change[] }): Outcome {
	if (result.error) return { failure: result.error };
	const id = result.entity?.id;
	const changes = result.undo && id ? [{ id, ...result.undo }] : [];
	return { changes: [...changes, ...(result.more ?? []), ...(result.closed ?? [])] };
}

function bulk(result: BulkResult): Outcome {
	return { failure: result.errors.length > 0 ? result.errors.join("; ") : undefined, changes: result.undo };
}

function plain(result: { error?: string }): Outcome {
	return { failure: result.error };
}

function guarded<T extends { error?: string }>(
	what: string,
	ids: string[],
	run: () => Promise<T>,
	outcome: (result: T) => Outcome,
): Promise<T> {
	const busy = busyWith(ids);
	if (busy) return Promise.resolve({ error: stillSaving(busy) } as T);
	return track(what, ids, run, outcome);
}

function guardedBulk<T extends BulkResult>(
	what: string,
	ids: string[],
	run: (progress: Progress) => Promise<T>,
): Promise<T> {
	const busy = busyWith(ids);
	if (busy) return Promise.resolve({ entities: [], undo: [], errors: [stillSaving(busy)] } as BulkResult as T);
	return track(what, ids, run, bulk);
}

async function inChunks<T>(
	items: T[],
	progress: (done: number, total: number) => void,
	run: (chunk: T[]) => Promise<BulkResult>,
): Promise<BulkResult> {
	const result: BulkResult = { entities: [], undo: [], errors: [] };
	if (items.length > CHUNK) progress(0, items.length);
	for (let start = 0; start < items.length; start += CHUNK) {
		const part = await run(items.slice(start, start + CHUNK));
		result.entities.push(...part.entities);
		result.undo.push(...part.undo);
		result.errors.push(...part.errors);
		if (items.length > CHUNK) progress(Math.min(start + CHUNK, items.length), items.length);
	}
	return result;
}

export async function dropCard(id: string, column: string, rank?: number, sets: FieldSet[] = []) {
	return guarded(`Moving ${id} to ${column}`, [id], () => raw.dropCard(id, column, rank, sets), single);
}

export async function editCard(id: string, field: string, value: string) {
	return guarded(`Changing the ${fieldName(field)} of ${id}`, [id], () => raw.editCard(id, field, value), single);
}

export async function closeProject(id: string) {
	return guarded(`Closing ${id} and everything open in it`, [id], () => raw.closeProject(id), single);
}

export async function linkCards(id: string, parent: string, child: string, linked: boolean) {
	return guarded(
		linked ? `Linking ${parent} to ${child}` : `Unlinking ${parent} from ${child}`,
		[parent, child],
		() => raw.linkCards(id, parent, child, linked),
		single,
	);
}

export async function saveBody(id: string, base: string, text: string) {
	return guarded(`Saving the content of ${id}`, [id], () => raw.saveBody(id, base, text), single);
}

export async function duplicateCard(id: string) {
	return guarded(`Duplicating ${id}`, [id], () => raw.duplicateCard(id), plain);
}

export async function archiveOne(id: string) {
	return guarded(`Archiving ${id}`, [id], () => raw.archiveOne(id), plain);
}

export async function removeMilestone(id: string) {
	return guarded(
		`Removing the milestone ${id}`,
		[id],
		() => raw.removeMilestone(id),
		(result) => ({ failure: result.error, changes: result.undo ? [{ id, ...result.undo }] : [] }),
	);
}

export async function undoChange(id: string, span: Span) {
	return guarded(`Undoing a change to ${id}`, [id], () => raw.undoChange(id, span), plain);
}

export async function restoreVersion(id: string, commit: string) {
	return guarded(`Restoring an earlier version of ${id}`, [id], () => raw.restoreVersion(id, commit), single);
}

export async function createCard(kind: Kind, name: string, status: string, options: NewOptions = {}) {
	return track(
		`Creating the ${kindName(kind)} ${name.trim()}`,
		[],
		() => raw.createCard(kind, name, status, options),
		plain,
	);
}

export async function finishEpic(id: string, cards: string[]) {
	return guardedBulk(`Deprioritising ${many(cards)} of ${id} and moving it to Epic Done`, [id, ...cards], () =>
		raw.finishEpic(id, cards),
	);
}

export async function finishEpics(ids: string[], cards: string[]) {
	return guardedBulk(`Deprioritising ${many(cards)} and moving ${many(ids)} to Epic Done`, [...ids, ...cards], () =>
		raw.finishEpics(ids, cards),
	);
}

function bulkWhat(ids: string[], change: Bulk) {
	if (change.op === "move") return `Moving ${many(ids)} to ${change.column}`;
	if (change.op === "set") return `Changing the ${fieldName(change.field)} of ${many(ids)}`;
	return `Archiving ${many(ids)}`;
}

export async function bulkChange(ids: string[], change: Bulk) {
	return guardedBulk(bulkWhat(ids, change), ids, (progress) =>
		inChunks(ids, progress, (part) => raw.bulkChange(part, change)),
	);
}

export async function rankPlan(order: Ranked[]) {
	const ids = order.map((one) => one.id);
	return guardedBulk(
		ids.length === 1 ? `Moving ${ids[0]} in the plan` : `Reordering ${ids.length} epics in the plan`,
		ids,
		(progress) => inChunks(order, progress, (part) => raw.rankPlan(part)),
	);
}

export type Undone = { change: Change; result: Awaited<ReturnType<typeof raw.undoChange>> };

export async function undoAll(changes: Change[], text: string): Promise<Undone[]> {
	if (changes.length === 0) return [];
	const ids = changes.map((change) => change.id);
	const busy = busyWith(ids);
	if (busy) return changes.map((change) => ({ change, result: { error: stillSaving(busy) } }));
	return track(
		`Undoing: ${text}`,
		ids,
		async (progress) => {
			const undone: Undone[] = [];
			if (changes.length > 1) progress(0, changes.length);
			for (const change of changes) {
				undone.push({ change, result: await raw.undoChange(change.id, { since: change.since, until: change.until }) });
				if (changes.length > 1) progress(undone.length, changes.length);
			}
			return undone;
		},
		(undone) => {
			const failures = undone.flatMap(({ result }) => (result.error ? [result.error] : []));
			return { failure: failures.length > 0 ? failures.join("; ") : undefined };
		},
	);
}
