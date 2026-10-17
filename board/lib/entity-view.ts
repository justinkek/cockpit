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
	listEntities,
	phaseOf,
	readAliases,
	readEntity,
	entityKindOf,
	resolveId,
} from "@/lib/board";
import { timeboxText } from "@/lib/shared";

export type Size = { text: string; title: string };

export type Member = Picked & { size?: Size };

function points(count: number) {
	return `${count} ${count === 1 ? "pt" : "pts"}`;
}

function sizeOf(card: Card): Size {
	if (card.type === "Timebox")
		return card.timebox_mins
			? { text: timeboxText(card.timebox_mins), title: `A timebox of ${card.timebox_mins} minutes` }
			: { text: "timebox", title: "A timebox with no length set" };
	if ((card.complexity ?? 0) > 0)
		return { text: points(card.complexity ?? 0), title: `TR complexity ${card.complexity}` };
	if ((card.estimate ?? 0) > 0)
		return { text: `~${points(card.estimate ?? 0)}`, title: `TD estimate ${card.estimate}, with no TR complexity yet` };
	return { text: "?", title: "Unsized: neither a TR complexity nor a TD estimate" };
}

export type EntityViewData = {
	entity: Card;
	lists: Lists;
	column: Card[];
	entities: Card[];
	attachments: string[];
	progresses: Record<string, Progress>;
	estimates?: Estimates;
	members: Member[];
};

export type EntityLookup = { view: EntityViewData } | { archived: Card } | { renamed: string } | { missing: string };

export async function lookupEntity(id: string): Promise<EntityLookup> {
	let entity: Card;
	try {
		entity = await readEntity(id);
	} catch (failure) {
		if (!(failure instanceof BoardError)) throw failure;
		const kind = entityKindOf(id.toUpperCase());
		if (kind && (await isArchived(id))) {
			const current = await resolveId(id);
			const archived = (await listEntities(kind, true)).find((other) => other.id === current);
			if (archived) return { archived };
		}
		const renamed = await findRenamed(id);
		if (renamed) return { renamed };
		return { missing: id.toUpperCase() };
	}
	if (entity.id !== id.toUpperCase()) return { renamed: entity.id };

	let cards: Card[] = [];
	let epics: Card[] = [];
	let sprints: Card[] = [];
	let projects: Card[] = [];
	let attachments: string[] = [];
	let aliases: Record<string, string> = {};
	try {
		[cards, epics, sprints, projects, aliases] = await Promise.all([
			listEntities("card"),
			listEntities("epic"),
			listEntities("sprint"),
			listEntities("project"),
			readAliases(),
		]);
		attachments = await listAttachments(entity.id);
	} catch (failure) {
		if (!(failure instanceof BoardError)) throw failure;
	}

	const entities = kindOf(entity.id) === "epic" ? epics : cards;
	const column = entities.filter((other) => other.status === entity.status);
	const progresses = Object.fromEntries(
		epics.map((epic) => [epic.id, progressOf(cards.filter((card) => card.epic === epic.id))]),
	);

	const kind = entityKindOf(entity.id);
	const epicsInProject = new Set(epics.filter((epic) => epic.project === entity.id).map((epic) => epic.id));
	const members =
		kind === "project"
			? [
					...epics.filter((epic) => epicsInProject.has(epic.id)),
					...cards.filter(
						(card) => card.project === entity.id || (!card.project && card.epic && epicsInProject.has(card.epic)),
					),
				]
			: kind === "sprint"
				? cards.filter((card) => card.sprint === entity.id)
				: kind === "epic"
					? cards.filter((card) => card.epic === entity.id)
					: [];

	return {
		view: {
			entity,
			column,
			entities,
			progresses,
			estimates: kind === "epic" ? estimatesOf(cards.filter((card) => card.epic === entity.id)) : undefined,
			attachments: attachments.map((file) => file.slice(file.lastIndexOf("/") + 1)),
			members: members
				.map((member) => ({
					id: member.id,
					name: member.name,
					status: member.status,
					...(kind === "epic" ? { size: sizeOf(member) } : {}),
				}))
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
