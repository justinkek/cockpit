import { Plan } from "@/app/plan";
import { BoardError, type Card, listRecords } from "@/lib/board";

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
	try {
		[cards, epics, projects, sprints, milestones] = await Promise.all([
			listRecords("card"),
			listRecords("epic"),
			listRecords("project"),
			listRecords("sprint"),
			listRecords("milestone"),
		]);
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return <p className="notice error">{error.message}</p>;
	}

	return (
		<Plan
			initial={epics}
			cards={cards.map(({ id, name, type, status, complexity, estimate, epic, dates, moved, dependent_on }) => ({
				id,
				name,
				type,
				status,
				complexity,
				estimate,
				epic,
				dates,
				moved,
				dependent_on,
				created: "",
				body: "",
			}))}
			milestones={milestones}
			projects={projects.map(({ id, name, icon, priority }) => ({ id, name, icon, priority }))}
			sprints={sprints.map(({ start, end, speed }) => ({ start, end, speed }))}
			today={today()}
			lists={{
				cards: cards.map(({ id, name, status }) => ({ id, name, status })),
				epics: epics.map(({ id, name, project }) => ({ id, name, project })),
				sprints: sprints.map(({ id, name, start, end }) => ({ id, name, start, end })),
				projects: projects.map(({ id, name }) => ({ id, name })),
			}}
		/>
	);
}
