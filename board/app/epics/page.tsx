import { Board } from "@/app/board";
import { BoardError, type Card, listEntities, readAliases, readViews, type SavedView } from "@/lib/board";

export const dynamic = "force-dynamic";

export default async function EpicsPage() {
	let cards: Card[];
	let epics: Card[];
	let projects: Card[];
	let views: SavedView[];
	let aliases: Record<string, string>;
	try {
		[cards, epics, projects, views, aliases] = await Promise.all([
			listEntities("card"),
			listEntities("epic"),
			listEntities("project"),
			readViews("epic"),
			readAliases(),
		]);
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return <p className="notice error">{error.message}</p>;
	}

	const children: Record<
		string,
		Pick<Card, "id" | "name" | "status" | "type" | "complexity" | "estimate" | "dependent_on">[]
	> = {};
	for (const card of cards) {
		if (!card.epic) continue;
		children[card.epic] ??= [];
		children[card.epic].push({
			id: card.id,
			name: card.name,
			status: card.status,
			type: card.type,
			complexity: card.complexity,
			estimate: card.estimate,
			dependent_on: card.dependent_on,
		});
	}

	return (
		<Board
			kind="epic"
			views={views}
			initial={epics}
			children={children}
			lists={{
				cards: cards.map(({ id, name, status }) => ({ id, name, status })),
				epics: epics.map(({ id, name, project, status }) => ({ id, name, project, status })),
				sprints: [],
				projects: projects.map(({ id, name, status }) => ({ id, name, status })),
				aliases,
			}}
		/>
	);
}
