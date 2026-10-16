import { Board } from "@/app/board";
import { BoardError, type Card, listRecords, manualRank } from "@/lib/board";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<{ view?: string | string[] }> };

export default async function CardsPage({ searchParams }: Props) {
	const { view } = await searchParams;
	let cards: Card[];
	let epics: Card[];
	let sprints: Card[];
	let projects: Card[];
	try {
		[cards, epics, sprints, projects] = await Promise.all([
			listRecords("card"),
			listRecords("epic"),
			listRecords("sprint"),
			listRecords("project"),
		]);
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return <p className="notice error">{error.message}</p>;
	}

	return (
		<Board
			kind="card"
			initial={cards}
			preset={typeof view === "string" ? view : undefined}
			lists={{
				cards: cards.map(({ id, name, status }) => ({ id, name, status })),
				epics: [...epics]
					.sort((a, b) => manualRank(a) - manualRank(b))
					.map(({ id, name, project }) => ({ id, name, project })),
				sprints: sprints.map(({ id, name, start, end }) => ({ id, name, start, end })),
				projects: projects.map(({ id, name }) => ({ id, name })),
			}}
		/>
	);
}
