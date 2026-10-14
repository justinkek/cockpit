import { notFound, redirect } from "next/navigation";
import { Ticket } from "@/app/ticket";
import { BoardError, type Card, findRenamed, listRecords, readRecord } from "@/lib/board";

export const dynamic = "force-dynamic";

type Props = {
	params: Promise<{ id: string }>;
};

export default async function CardPage({ params }: Props) {
	const { id } = await params;
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
	try {
		[cards, epics, sprints, projects] = await Promise.all([
			listRecords("card"),
			listRecords("epic"),
			listRecords("sprint"),
			listRecords("project"),
		]);
	} catch (failure) {
		if (!(failure instanceof BoardError)) throw failure;
	}

	return (
		<Ticket
			initial={record}
			cards={cards.map(({ id, name, status }) => ({ id, name, status }))}
			epics={epics.map(({ id, name }) => ({ id, name }))}
			sprints={sprints.map(({ id, name, start, end }) => ({ id, name, start, end }))}
			projects={projects.map(({ id, name }) => ({ id, name }))}
		/>
	);
}
