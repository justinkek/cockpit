import { notFound, redirect } from "next/navigation";
import { Ticket } from "@/app/ticket";
import { BoardError, type Card, findRenamed, kindOf, listAttachments, listRecords, readRecord } from "@/lib/board";

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

	return (
		<Ticket
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
