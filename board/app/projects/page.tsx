import { type ProjectEntry, Projects } from "@/app/projects";
import { BoardError, type Card, listRecords, phaseOf } from "@/lib/board";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<{ error?: string | string[] }> };

export default async function ProjectsPage({ searchParams }: Props) {
	const { error } = await searchParams;
	let projects: Card[];
	let epics: Card[];
	let cards: Card[];
	try {
		[projects, epics, cards] = await Promise.all([listRecords("project"), listRecords("epic"), listRecords("card")]);
	} catch (failure) {
		if (!(failure instanceof BoardError)) throw failure;
		return <p className="notice error">{failure.message}</p>;
	}

	const projectOfEpic = new Map(epics.map((epic) => [epic.id, epic.project ?? null]));
	const counts = new Map<string, { epics: number; openEpics: number; open: number; done: number }>();
	const tally = (id: string | null | undefined) => {
		if (!id) return null;
		const count = counts.get(id) ?? { epics: 0, openEpics: 0, open: 0, done: 0 };
		counts.set(id, count);
		return count;
	};
	for (const epic of epics) {
		const count = tally(epic.project);
		if (!count) continue;
		count.epics += 1;
		if (epic.status !== "Epic Done") count.openEpics += 1;
	}
	for (const card of cards) {
		const count = tally(card.project ?? (card.epic ? projectOfEpic.get(card.epic) : null));
		if (!count || card.status === "Deprioritised") continue;
		if (phaseOf(card.status) === "done") count.done += 1;
		else count.open += 1;
	}

	const entries: ProjectEntry[] = projects.map((project) => ({
		id: project.id,
		name: project.name,
		key: project.key,
		icon: project.icon,
		status: project.status,
		priority: project.priority,
		tracks: project.tracks,
		...(counts.get(project.id) ?? { epics: 0, openEpics: 0, open: 0, done: 0 }),
	}));

	return <Projects initial={entries} error={typeof error === "string" ? error : undefined} />;
}
