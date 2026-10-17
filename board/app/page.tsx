import { Board } from "@/app/board";
import { BoardError, type Card, listRecords, manualRank, readAliases, readViews, type SavedView } from "@/lib/board";

export const dynamic = "force-dynamic";

export default async function CardsPage() {
	let cards: Card[];
	let epics: Card[];
	let sprints: Card[];
	let projects: Card[];
	let views: SavedView[];
	let aliases: Record<string, string>;
	try {
		[cards, epics, sprints, projects, views, aliases] = await Promise.all([
			listRecords("card"),
			listRecords("epic"),
			listRecords("sprint"),
			listRecords("project"),
			readViews("card"),
			readAliases(),
		]);
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return <p className="notice error">{error.message}</p>;
	}

	return (
		<Board
			kind="card"
			views={views}
			initial={cards}
			lists={{
				cards: cards.map(({ id, name, status }) => ({ id, name, status })),
				epics: [...epics]
					.sort((a, b) => manualRank(a) - manualRank(b))
					.map(({ id, name, project, status }) => ({ id, name, project, status })),
				sprints: sprints.map(({ id, name, start, end }) => ({ id, name, start, end })),
				projects: projects.map(({ id, name, status }) => ({ id, name, status })),
				aliases,
			}}
		/>
	);
}
