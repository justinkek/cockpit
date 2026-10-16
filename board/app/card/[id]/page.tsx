import { notFound, redirect } from "next/navigation";
import { ArchivedRecord } from "@/app/archived";
import { Ticket } from "@/app/ticket";
import { progressOf } from "@/lib/metrics";
import { estimatesOf } from "@/lib/plan";
import {
	BoardError,
	type Card,
	findRenamed,
	isArchived,
	kindOf,
	listAttachments,
	listRecords,
	phaseOf,
	readRecord,
	recordKindOf,
} from "@/lib/board";

export const dynamic = "force-dynamic";

type Props = {
	params: Promise<{ id: string }>;
	searchParams: Promise<{ error?: string | string[] }>;
};

export default async function CardPage({ params, searchParams }: Props) {
	const { id } = await params;
	const { error } = await searchParams;
	let record: Card;
	try {
		record = await readRecord(id);
	} catch (failure) {
		if (!(failure instanceof BoardError)) throw failure;
		const kind = recordKindOf(id.toUpperCase());
		if (kind && (await isArchived(id))) {
			const archived = (await listRecords(kind, true)).find((other) => other.id === id.toUpperCase());
			if (archived) return <ArchivedRecord record={archived} failure={typeof error === "string" ? error : undefined} />;
		}
		const renamed = await findRenamed(id);
		if (renamed) redirect(`/card/${renamed}`);
		notFound();
	}

	let cards: Card[] = [];
	let epics: Card[] = [];
	let sprints: Card[] = [];
	let projects: Card[] = [];
	let attachments: string[] = [];
	try {
		[cards, epics, sprints, projects] = await Promise.all([
			listRecords("card"),
			listRecords("epic"),
			listRecords("sprint"),
			listRecords("project"),
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
				: [];

	return (
		<Ticket
			members={members
				.map(({ id, name, status }) => ({ id, name, status }))
				.sort((a, b) => Number(phaseOf(a.status) === "done") - Number(phaseOf(b.status) === "done"))}
			progresses={progresses}
			estimates={kind === "epic" ? estimatesOf(cards.filter((card) => card.epic === record.id)) : undefined}
			initial={record}
			column={column}
			records={records}
			failure={typeof error === "string" ? error : undefined}
			attachments={attachments.map((file) => file.slice(file.lastIndexOf("/") + 1))}
			lists={{
				cards: cards.map(({ id, name, status }) => ({ id, name, status })),
				epics: epics.map(({ id, name, project }) => ({ id, name, project })),
				sprints: sprints.map(({ id, name, start, end }) => ({ id, name, start, end })),
				projects: projects.map(({ id, name }) => ({ id, name })),
			}}
		/>
	);
}
