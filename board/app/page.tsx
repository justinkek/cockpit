import { Board } from "@/app/board";
import { BoardError, type Card, listRecords } from "@/lib/board";

export const dynamic = "force-dynamic";

export default async function CardsPage() {
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

	if (cards.length === 0) {
		return <p className="notice">No cards yet. Create one with board-card create --name ….</p>;
	}

	return (
		<Board
			kind="card"
			initial={cards}
			lists={{
				cards: cards.map(({ id, name, status }) => ({ id, name, status })),
				epics: epics.map(({ id, name }) => ({ id, name })),
				sprints: sprints.map(({ id, name, start, end }) => ({ id, name, start, end })),
				projects: projects.map(({ id, name }) => ({ id, name })),
			}}
		/>
	);
}
