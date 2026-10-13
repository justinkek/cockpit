import { Board } from "@/app/board";
import { BoardError, type Card, listRecords } from "@/lib/board";

export const dynamic = "force-dynamic";

export default async function CardsPage() {
	let cards: Card[];
	let epics: Card[];
	try {
		[cards, epics] = await Promise.all([listRecords("card"), listRecords("epic")]);
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return <p className="notice error">{error.message}</p>;
	}

	if (cards.length === 0) {
		return <p className="notice">No cards yet. Create one with board-card create --name ….</p>;
	}

	return <Board kind="card" initial={cards} epics={epics.map(({ id, name }) => ({ id, name }))} />;
}
