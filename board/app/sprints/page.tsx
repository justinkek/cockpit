import Link from "next/link";
import { BurndownChart } from "@/app/burndown";
import { SprintPicker } from "@/app/picker";
import { BoardError, type Card, listRecords, phaseOf } from "@/lib/board";
import { burndownOf, currentSprint, type Measure, sprintDays } from "@/lib/metrics";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<{ sprint?: string | string[]; measure?: string | string[] }> };

function sprintLabel(sprint: Card) {
	return sprint.start ? `${sprint.name} · ${sprint.start} to ${sprint.end ?? "?"}` : sprint.name;
}

function today() {
	const now = new Date();
	return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}

export default async function SprintsPage({ searchParams }: Props) {
	const params = await searchParams;
	let cards: Card[];
	let sprints: Card[];
	try {
		[cards, sprints] = await Promise.all([listRecords("card"), listRecords("sprint")]);
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return <p className="notice error">{error.message}</p>;
	}

	if (sprints.length === 0) {
		return (
			<section className="report">
				<h1>Sprints</h1>
				<p className="empty">No sprint is on the board yet.</p>
			</section>
		);
	}

	const ordered = [...sprints].sort((a, b) => (b.start ?? "").localeCompare(a.start ?? ""));
	const wanted = typeof params.sprint === "string" ? params.sprint : null;
	const sprint = ordered.find((candidate) => candidate.id === wanted) ?? currentSprint(ordered) ?? ordered[0];
	const measure: Measure = params.measure === "cards" ? "cards" : "points";
	const unit = measure === "cards" ? "Cards" : "Points";
	const inSprint = cards.filter((card) => card.sprint === sprint.id);
	const counted = inSprint.filter((card) => card.status !== "Deprioritised");
	const burndown = burndownOf(sprint, inSprint, measure);
	const done = counted.filter((card) => phaseOf(card.status) === "done");
	const points = (list: Card[]) => list.reduce((sum, card) => sum + (card.complexity ?? 0), 0);
	const daysLeft = sprintDays(sprint.start, sprint.end).filter((day) => day >= today()).length;
	const unsized = counted.filter((card) => card.complexity == null).length;
	const sorted = [...inSprint].sort(
		(a, b) => Number(phaseOf(a.status) === "done") - Number(phaseOf(b.status) === "done") || a.id.localeCompare(b.id),
	);

	return (
		<section className="report">
			<header className="report-head">
				<h1>Sprint burndown</h1>
				<SprintPicker
					sprints={ordered.map((candidate) => ({ id: candidate.id, label: sprintLabel(candidate) }))}
					value={sprint.id}
					measure={measure}
				/>
				<span className="segmented" role="group" aria-label="Burn down by">
					{(["points", "cards"] as const).map((option) => (
						<Link
							key={option}
							href={`/sprints?sprint=${sprint.id}&measure=${option}`}
							className={option === measure ? "on" : undefined}
							aria-current={option === measure ? "true" : undefined}
						>
							{option === "points" ? "Points" : "Cards"}
						</Link>
					))}
				</span>
			</header>

			<div className="stat-row">
				<div>
					<span className="stat-label">Scope</span>
					<span className="stat-value">
						{points(counted)} <span>pts · {counted.length} cards</span>
					</span>
				</div>
				<div>
					<span className="stat-label">Done</span>
					<span className="stat-value">
						{points(done)} <span>pts · {done.length} cards</span>
					</span>
				</div>
				<div>
					<span className="stat-label">Left</span>
					<span className="stat-value">
						{points(counted) - points(done)} <span>pts · {counted.length - done.length} cards</span>
					</span>
				</div>
				<div>
					<span className="stat-label">Working days left</span>
					<span className="stat-value">{daysLeft}</span>
				</div>
			</div>

			<div className="report-card">
				<h2>
					{unit} left in {sprint.name}
				</h2>
				{measure === "points" && unsized > 0 && (
					<p className="report-note">
						{unsized} {unsized === 1 ? "card has" : "cards have"} no points and {unsized === 1 ? "does" : "do"} not show
						in this burndown - burn down by cards to count {unsized === 1 ? "it" : "them"}.
					</p>
				)}
				<BurndownChart burndown={burndown} unit={unit} />
			</div>

			<div className="report-card">
				<h2>
					Cards in {sprint.name} <span className="count">{inSprint.length}</span>
				</h2>
				{sorted.length === 0 ? (
					<p className="empty">No card is in this sprint. Set a card's sprint on its panel.</p>
				) : (
					<ul className="report-list">
						{sorted.map((card) => (
							<li key={card.id}>
								<span className={`dot phase-${phaseOf(card.status)}`} aria-hidden="true" />
								<span className="ident">{card.id}</span>
								<Link href={`/card/${card.id}`} className="report-name">
									{card.name}
								</Link>
								<span className="report-status">{card.status}</span>
								<span className="points">{card.complexity ?? ""}</span>
							</li>
						))}
					</ul>
				)}
			</div>
		</section>
	);
}
