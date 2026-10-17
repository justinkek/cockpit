import Link from "next/link";
import { BurndownChart } from "@/app/burndown";
import { NewOther } from "@/app/new-record";
import { SprintPicker } from "@/app/picker";
import { SprintDates } from "@/app/record-fields";
import { type Card, phaseOf } from "@/lib/board";
import { burndownOf, currentSprint, type Measure, sprintDays } from "@/lib/metrics";
import { deliveredIn } from "@/lib/plan";

export type SprintParams = {
	sprint?: string | string[];
	measure?: string | string[];
	error?: string | string[];
};

function sprintLabel(sprint: Card) {
	if (sprint.start && sprint.end) return `${sprint.name} · ${sprint.start} to ${sprint.end}`;
	if (sprint.start) return `${sprint.name} · from ${sprint.start}`;
	if (sprint.end) return `${sprint.name} · until ${sprint.end}`;
	return sprint.name;
}

function today() {
	const now = new Date();
	return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}

function sprintHref(id: string, measure: Measure) {
	return `/obeya?sprint=${encodeURIComponent(id)}&measure=${measure}#sprint`;
}

export function SprintSection({ cards, sprints, params }: { cards: Card[]; sprints: Card[]; params: SprintParams }) {
	const failure =
		typeof params.error === "string" ? (
			<p className="notice error" role="alert">
				{params.error}
			</p>
		) : null;

	if (sprints.length === 0) {
		return (
			<section className="obeya-sprint" id="sprint" aria-labelledby="sprint-heading">
				<header className="report-head">
					<h2 id="sprint-heading">Sprint</h2>
					<span className="spacer" />
					<NewOther kind="sprint" />
				</header>
				{failure}
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
		<section className="obeya-sprint" id="sprint" aria-labelledby="sprint-heading">
			<header className="report-head">
				<h2 id="sprint-heading">Sprint</h2>
				<SprintPicker
					sprints={ordered.map((candidate) => ({ id: candidate.id, label: sprintLabel(candidate) }))}
					value={sprint.id}
					measure={measure}
				/>
				<span className="segmented" role="group" aria-label="Burn down by">
					{(["points", "cards"] as const).map((option) => (
						<Link
							key={option}
							href={sprintHref(sprint.id, option)}
							scroll={false}
							className={option === measure ? "on" : undefined}
							aria-current={option === measure ? "true" : undefined}
						>
							{option === "points" ? "Points" : "Cards"}
						</Link>
					))}
				</span>
				<span className="spacer" />
				<NewOther kind="sprint" />
			</header>
			{failure}
			<SprintDates sprint={sprint} />

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
						{unsized} {unsized === 1 ? "card has" : "cards have"} no points and {unsized === 1 ? "does" : "do"} not
						show in this burndown - burn down by cards to count {unsized === 1 ? "it" : "them"}.
					</p>
				)}
				<BurndownChart burndown={burndown} unit={unit} sprint={sprint} />
			</div>

			<div className="report-card">
				<h2>
					Speed by sprint <span className="count">{ordered.length}</span>
				</h2>
				<p className="report-note">
					The TR complexity of every card done within each sprint's dates, whatever sprint the card was in, and that
					a week - a card done without a complexity, or a timebox, is counted beside it.
				</p>
				<ul className="report-list">
					{ordered.map((candidate) => {
						const delivered = deliveredIn(candidate, cards);
						const beside = [
							delivered.uncounted > 0 ? `${delivered.uncounted} without complexity` : "",
							delivered.timeboxes > 0
								? `${delivered.timeboxes} ${delivered.timeboxes === 1 ? "timebox" : "timeboxes"}`
								: "",
						].filter(Boolean);
						return (
							<li key={candidate.id}>
								<span className="ident">{candidate.id}</span>
								<Link href={sprintHref(candidate.id, measure)} scroll={false} className="report-name">
									{sprintLabel(candidate)}
								</Link>
								<span className="report-status">
									{delivered.perWeek == null
										? "no dates"
										: `${delivered.points} pts from ${delivered.tickets} ${delivered.tickets === 1 ? "card" : "cards"}${beside.length > 0 ? ` + ${beside.join(" + ")}` : ""}`}
								</span>
								<span className="points">{delivered.perWeek == null ? "" : `${delivered.perWeek}/wk`}</span>
							</li>
						);
					})}
				</ul>
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
