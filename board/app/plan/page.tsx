import { Plan } from "@/app/plan";
import { BoardError, type Break, boardTracks, type Card, listRecords, readBreaks } from "@/lib/board";

export const dynamic = "force-dynamic";

function today() {
	const now = new Date();
	return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}

export default async function PlanPage() {
	let cards: Card[];
	let epics: Card[];
	let projects: Card[];
	let sprints: Card[];
	let milestones: Card[];
	let tracks: number;
	let breaks: Break[];
	try {
		[cards, epics, projects, sprints, milestones, tracks, breaks] = await Promise.all([
			listRecords("card"),
			listRecords("epic"),
			listRecords("project"),
			listRecords("sprint"),
			listRecords("milestone"),
			boardTracks(),
			readBreaks(),
		]);
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return <p className="notice error">{error.message}</p>;
	}

	return (
		<Plan
			initial={epics}
			cards={cards.map(
				({ id, name, type, status, complexity, estimate, epic, project, dates, moved, dependent_on }) => ({
					id,
					name,
					type,
					status,
					complexity,
					estimate,
					epic,
					project,
					dates,
					moved,
					dependent_on,
					created: "",
					body: "",
				}),
			)}
			milestones={milestones}
			tracks={tracks}
			breaks={breaks}
			projects={projects.map(({ id, name, icon, priority, tracks, status }) => ({ id, name, icon, priority, tracks, status }))}
			sprints={sprints.map(({ start, end, speed }) => ({ start, end, speed }))}
			today={today()}
			lists={{
				cards: cards.map(({ id, name, status }) => ({ id, name, status })),
				epics: epics.map(({ id, name, project, status }) => ({ id, name, project, status })),
				sprints: sprints.map(({ id, name, start, end }) => ({ id, name, start, end })),
				projects: projects.map(({ id, name }) => ({ id, name })),
			}}
		/>
	);
}
