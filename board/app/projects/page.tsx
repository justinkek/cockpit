import Link from "next/link";
import { NewOther } from "@/app/new-record";
import { BoardError, type Card, listRecords, phaseOf } from "@/lib/board";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<{ error?: string | string[] }> };

const PHASES: Record<string, string> = { "Not started": "idle", "In progress": "dev", Done: "done" };

const ORDER = ["In progress", "Not started", "Done"];

function plural(count: number, one: string) {
	return `${count} ${one}${count === 1 ? "" : "s"}`;
}

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
	const counts = new Map<string, { epics: number; open: number; done: number }>();
	const tally = (id: string | null | undefined) => {
		if (!id) return null;
		const count = counts.get(id) ?? { epics: 0, open: 0, done: 0 };
		counts.set(id, count);
		return count;
	};
	for (const epic of epics) {
		const count = tally(epic.project);
		if (count) count.epics += 1;
	}
	for (const card of cards) {
		const count = tally(card.project ?? (card.epic ? projectOfEpic.get(card.epic) : null));
		if (!count || card.status === "Deprioritised") continue;
		if (phaseOf(card.status) === "done") count.done += 1;
		else count.open += 1;
	}

	const groups = [
		...ORDER,
		...new Set(projects.map((project) => project.status).filter((status) => !ORDER.includes(status))),
	]
		.map((status) => ({
			status,
			projects: projects
				.filter((project) => project.status === status)
				.sort(
					(a, b) =>
						(a.priority ?? Number.POSITIVE_INFINITY) - (b.priority ?? Number.POSITIVE_INFINITY) ||
						a.name.localeCompare(b.name),
				),
		}))
		.filter((group) => group.projects.length > 0);

	return (
		<section className="report">
			<header className="report-head">
				<h1>Projects</h1>
				<span className="count">{projects.length}</span>
				<span className="spacer" />
				<NewOther kind="project" />
			</header>
			{typeof error === "string" && (
				<p className="notice error" role="alert">
					{error}
				</p>
			)}
			{groups.length === 0 && <p className="empty">No project is on the board yet.</p>}
			{groups.map((group) => (
				<div key={group.status} className="report-card">
					<h2>
						<span className={`dot phase-${PHASES[group.status] ?? "idle"}`} aria-hidden="true" />
						{group.status || "No status"} <span className="count">{group.projects.length}</span>
					</h2>
					<ul className="record-list">
						{group.projects.map((project) => {
							const count = counts.get(project.id) ?? { epics: 0, open: 0, done: 0 };
							return (
								<li key={project.id}>
									<span className="ident">{project.id}</span>
									<Link href={`/card/${project.id}`} className="report-name">
										{project.icon && <span className="record-icon">{project.icon}</span>}
										{project.name.trim() || "(untitled)"}
									</Link>
									<span className="record-meta">
										{project.priority != null && <span className="pill">P{project.priority}</span>}
										<span title={`${count.open} open, ${count.done} done`}>
											{plural(count.epics, "epic")} · {count.open} open · {count.done} done
										</span>
									</span>
								</li>
							);
						})}
					</ul>
				</div>
			))}
		</section>
	);
}
