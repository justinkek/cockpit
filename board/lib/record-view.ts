import type { Lists, Picked } from "@/app/fields";
import { type Progress, progressOf } from "@/lib/metrics";
import { type Estimates, estimatesOf } from "@/lib/plan";
import {
	BoardError,
	type Card,
	findRenamed,
	isArchived,
	kindOf,
	listAttachments,
	listRecords,
	phaseOf,
	readAliases,
	readRecord,
	recordKindOf,
	resolveId,
} from "@/lib/board";

export type RecordViewData = {
	record: Card;
	lists: Lists;
	column: Card[];
	records: Card[];
	attachments: string[];
	progresses: Record<string, Progress>;
	estimates?: Estimates;
	members: Picked[];
};

export type RecordLookup = { view: RecordViewData } | { archived: Card } | { renamed: string } | { missing: string };

export async function lookupRecord(id: string): Promise<RecordLookup> {
	let record: Card;
	try {
		record = await readRecord(id);
	} catch (failure) {
		if (!(failure instanceof BoardError)) throw failure;
		const kind = recordKindOf(id.toUpperCase());
		if (kind && (await isArchived(id))) {
			const current = await resolveId(id);
			const archived = (await listRecords(kind, true)).find((other) => other.id === current);
			if (archived) return { archived };
		}
		const renamed = await findRenamed(id);
		if (renamed) return { renamed };
		return { missing: id.toUpperCase() };
	}
	if (record.id !== id.toUpperCase()) return { renamed: record.id };

	let cards: Card[] = [];
	let epics: Card[] = [];
	let sprints: Card[] = [];
	let projects: Card[] = [];
	let attachments: string[] = [];
	let aliases: Record<string, string> = {};
	try {
		[cards, epics, sprints, projects, aliases] = await Promise.all([
			listRecords("card"),
			listRecords("epic"),
			listRecords("sprint"),
			listRecords("project"),
			readAliases(),
		]);
		attachments = await listAttachments(record.id);
	} catch (failure) {
		if (!(failure instanceof BoardError)) throw failure;
	}

	const records = kindOf(record.id) === "epic" ? epics : cards;
	const column = records.filter((other) => other.status === record.status);
	const progresses = Object.fromEntries(
		epics.map((epic) => [epic.id, progressOf(cards.filter((card) => card.epic === epic.id))]),
	);

	const kind = recordKindOf(record.id);
	const epicsInProject = new Set(epics.filter((epic) => epic.project === record.id).map((epic) => epic.id));
	const members =
		kind === "project"
			? [
					...epics.filter((epic) => epicsInProject.has(epic.id)),
					...cards.filter(
						(card) => card.project === record.id || (!card.project && card.epic && epicsInProject.has(card.epic)),
					),
				]
			: kind === "sprint"
				? cards.filter((card) => card.sprint === record.id)
				: kind === "epic"
					? cards.filter((card) => card.epic === record.id)
					: [];

	return {
		view: {
			record,
			column,
			records,
			progresses,
			estimates: kind === "epic" ? estimatesOf(cards.filter((card) => card.epic === record.id)) : undefined,
			attachments: attachments.map((file) => file.slice(file.lastIndexOf("/") + 1)),
			members: members
				.map(({ id, name, status }) => ({ id, name, status }))
				.sort((a, b) => Number(phaseOf(a.status) === "done") - Number(phaseOf(b.status) === "done")),
			lists: {
				cards: cards.map(({ id, name, status }) => ({ id, name, status })),
				epics: epics.map(({ id, name, project, status }) => ({ id, name, project, status })),
				sprints: sprints.map(({ id, name, start, end }) => ({ id, name, start, end })),
				projects: projects.map(({ id, name, status }) => ({ id, name, status })),
				aliases,
			},
		},
	};
}
