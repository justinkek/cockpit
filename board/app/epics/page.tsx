import { Board } from "@/app/board";
import { BoardError, type Card, listRecords } from "@/lib/board";

export const dynamic = "force-dynamic";

export default async function EpicsPage() {
	let cards: Card[];
	let epics: Card[];
	let projects: Card[];
	try {
		[cards, epics, projects] = await Promise.all([listRecords("card"), listRecords("epic"), listRecords("project")]);
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return <p className="notice error">{error.message}</p>;
	}

	if (epics.length === 0) {
		return <p className="notice">No epics yet. Create one with board-card create --kind epic --name ….</p>;
	}

	const children: Record<string, { id: string; name: string; status: string }[]> = {};
	for (const card of cards) {
		if (!card.epic) continue;
		children[card.epic] ??= [];
		children[card.epic].push({ id: card.id, name: card.name, status: card.status });
	}

	return (
		<Board
			kind="epic"
			initial={epics}
			children={children}
			lists={{
				cards: cards.map(({ id, name, status }) => ({ id, name, status })),
				epics: epics.map(({ id, name }) => ({ id, name })),
				sprints: [],
				projects: projects.map(({ id, name }) => ({ id, name })),
			}}
		/>
	);
}
