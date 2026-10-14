import { notFound, redirect } from "next/navigation";
import { Ticket } from "@/app/ticket";
import { BoardError, type Card, findRenamed, kindOf, listRecords, manualRank, readRecord } from "@/lib/board";

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

	const kind = kindOf(record.id);
	const column = (kind === "epic" ? epics : cards)
		.filter((other) => other.status === record.status)
		.sort((a, b) => manualRank(a) - manualRank(b));
	const index = column.findIndex((other) => other.id === record.id);
	const near = (other?: Card) => (other ? { id: other.id, name: other.name } : null);
	const neighbours =
		index < 0
			? null
			: { previous: near(column[index - 1]), next: near(column[index + 1]), position: index + 1, total: column.length };

	return (
		<Ticket
			initial={record}
			neighbours={neighbours}
			failure={typeof error === "string" ? error : undefined}
			lists={{
				cards: cards.map(({ id, name, status }) => ({ id, name, status })),
				epics: epics.map(({ id, name }) => ({ id, name })),
				sprints: sprints.map(({ id, name, start, end }) => ({ id, name, start, end })),
				projects: projects.map(({ id, name }) => ({ id, name })),
			}}
		/>
	);
}
