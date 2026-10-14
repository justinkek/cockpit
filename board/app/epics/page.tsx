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

	const children: Record<string, { id: string; name: string; status: string; complexity?: number | null }[]> = {};
	for (const card of cards) {
		if (!card.epic) continue;
		children[card.epic] ??= [];
		children[card.epic].push({ id: card.id, name: card.name, status: card.status, complexity: card.complexity });
	}

	return (
		<Board
			kind="epic"
			initial={epics}
			children={children}
			lists={{
				cards: cards.map(({ id, name, status }) => ({ id, name, status })),
				epics: epics.map(({ id, name, project }) => ({ id, name, project })),
				sprints: [],
				projects: projects.map(({ id, name }) => ({ id, name })),
			}}
		/>
	);
}
