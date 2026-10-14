import Link from "next/link";
import { BurndownChart } from "@/app/burndown";
import { ProgressMeter } from "@/app/progress";
import {
	BoardError,
	CARD_COLUMNS,
	type Card,
	doneWithin,
	listRecords,
	overrunTitle,
	phaseOf,
	showsOverrun,
	wipLimit,
} from "@/lib/board";
import { burndownOf, currentSprint, flowOf, median, progressOf, span, throughputOf } from "@/lib/metrics";

export const dynamic = "force-dynamic";

const AGED_AFTER = 5;
const WEEKS = 8;
const ATTENTION = 12;
const FLOW_COLUMNS = CARD_COLUMNS.filter((column) => !["Backlog", "Done"].includes(column));
const ACTIVE = ["dev", "review", "validate"];

type Reason = { label: string; tone: string; title: string };

function reasonsFor(card: Card): Reason[] {
	const reasons: Reason[] = [];
	if (card.blocked) reasons.push({ label: "Blocked", tone: "blocked", title: card.blocked });
	if (showsOverrun(card)) reasons.push({ label: "Overrunning", tone: "overrun", title: overrunTitle(card) });
	const days = card.days_in_column ?? 0;
	if (days >= AGED_AFTER)
		reasons.push({ label: `${days}d`, tone: "days aged", title: `${days} working days in ${card.status}` });
	return reasons;
}

function weekLabel(start: string) {
	const [year, month, day] = start.split("-").map(Number);
	return new Date(year, month - 1, day).toLocaleDateString(undefined, { day: "numeric", month: "short" });
}

export default async function ObeyaPage() {
	let cards: Card[];
	let epics: Card[];
	let sprints: Card[];
	try {
		[cards, epics, sprints] = await Promise.all([listRecords("card"), listRecords("epic"), listRecords("sprint")]);
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return <p className="notice error">{error.message}</p>;
	}

	const now = Date.now();
	const open = cards.filter((card) => phaseOf(card.status) !== "done" && card.status !== "Deprioritised");
	const active = cards.filter((card) => ACTIVE.includes(phaseOf(card.status)));
	const blocked = open.filter((card) => card.blocked);
	const overrunning = cards.filter(showsOverrun);
	const doneThisWeek = cards.filter((card) => card.status === "Done" && doneWithin(card, 7, now));
	const recentCycles = cards
		.filter((card) => card.status === "Done" && doneWithin(card, 30, now))
		.map((card) => flowOf(card, now).cycle)
		.filter((cycle): cycle is number => cycle != null);
	const cycle = median(recentCycles);

	const counts = Object.fromEntries(
		FLOW_COLUMNS.map((column) => [column, cards.filter((card) => card.status === column).length]),
	);
	const flowTop = Math.max(1, ...FLOW_COLUMNS.map((column) => Math.max(counts[column], wipLimit("card", column) ?? 0)));

	const weeks = throughputOf(cards, WEEKS, new Date(now));
	const weekTop = Math.max(1, ...weeks.map((week) => week.done));

	const sprint = currentSprint(sprints);
	const sprintCards = sprint ? cards.filter((card) => card.sprint === sprint.id) : [];
	const burndown = sprint ? burndownOf(sprint, sprintCards, "points", now) : null;

	const children: Record<string, Card[]> = {};
	for (const card of cards) if (card.epic) (children[card.epic] ??= []).push(card);
	const epicsInFlight = epics
		.filter((epic) => phaseOf(epic.status) !== "done")
		.map((epic) => ({ epic, progress: progressOf(children[epic.id] ?? []) }))
		.filter(({ epic, progress }) => progress.total > progress.done || phaseOf(epic.status) === "dev")
		.sort((a, b) => b.progress.total - b.progress.done - (a.progress.total - a.progress.done));

	const attention = open
		.map((card) => ({ card, reasons: reasonsFor(card) }))
		.filter(({ reasons }) => reasons.length > 0)
		.sort((a, b) => b.reasons.length - a.reasons.length || (b.card.days_in_column ?? 0) - (a.card.days_in_column ?? 0));

	return (
		<section className="report obeya">
			<header className="report-head">
				<h1>Obeya</h1>
				<span className="report-note">Everything in flight on the board, in one room</span>
			</header>

			<div className="stat-row">
				<Link href="/?view=sprint">
					<span className="stat-label">In progress</span>
					<span className="stat-value">
						{active.length} <span>in dev, review or validation</span>
					</span>
				</Link>
				<div className={blocked.length > 0 ? "alert" : undefined}>
					<span className="stat-label">Blocked</span>
					<span className="stat-value">{blocked.length}</span>
				</div>
				<div className={overrunning.length > 0 ? "alert" : undefined}>
					<span className="stat-label">Overrunning</span>
					<span className="stat-value">{overrunning.length}</span>
				</div>
				<Link href="/?view=week">
					<span className="stat-label">Done in the last 7 days</span>
					<span className="stat-value">{doneThisWeek.length}</span>
				</Link>
				<div title={`The median from In Dev to Done of the ${recentCycles.length} cards done in the last 30 days`}>
					<span className="stat-label">Median cycle time</span>
					<span className="stat-value">
						{cycle == null ? "-" : span(cycle)} <span>last 30 days</span>
					</span>
				</div>
			</div>

			<div className="obeya-grid">
				<div className="report-card">
					<h2>
						Flow <span className="count">cards in each column against its WIP limit</span>
					</h2>
					<ul className="flow-bars">
						{FLOW_COLUMNS.map((column) => {
							const count = counts[column];
							const limit = wipLimit("card", column);
							const over = limit != null && count > limit;
							return (
								<li
									key={column}
									title={limit == null ? `${count} in ${column}` : `${count} in ${column}, of a WIP limit of ${limit}`}
								>
									<span className="flow-name">
										<span className={`dot phase-${phaseOf(column)}`} aria-hidden="true" />
										{column}
									</span>
									<span className="flow-track">
										<span
											className={`flow-fill phase-${phaseOf(column)}${over ? " over" : ""}`}
											style={{ width: `${(count / flowTop) * 100}%` }}
										/>
										{limit != null && <span className="flow-limit" style={{ left: `${(limit / flowTop) * 100}%` }} />}
									</span>
									<span className={`flow-count${over ? " over" : ""}`}>
										{count}
										{limit != null && <span>/{limit}</span>}
									</span>
								</li>
							);
						})}
					</ul>
				</div>

				<div className="report-card">
					<h2>
						{sprint ? `Sprint ${sprint.name}` : "Sprint"}
						<Link href={sprint ? `/sprints?sprint=${sprint.id}` : "/sprints"}>Open the burndown</Link>
					</h2>
					{burndown ? (
						<BurndownChart burndown={burndown} unit="Points" compact />
					) : (
						<p className="empty">No sprint is on the board yet.</p>
					)}
				</div>

				<div className="report-card">
					<h2>
						Throughput <span className="count">cards done each week</span>
					</h2>
					<ol className="week-bars">
						{weeks.map((week) => (
							<li
								key={week.start}
								title={`${week.done} ${week.done === 1 ? "card" : "cards"} and ${week.points} points done in the week of ${weekLabel(week.start)}`}
							>
								<span className="week-value">{week.done}</span>
								<span className="week-track">
									<span style={{ height: `${(week.done / weekTop) * 100}%` }} />
								</span>
								<span className="week-label">{weekLabel(week.start)}</span>
							</li>
						))}
					</ol>
				</div>

				<div className="report-card">
					<h2>
						Epics in flight <span className="count">{epicsInFlight.length}</span>
						<Link href="/epics">All epics</Link>
					</h2>
					{epicsInFlight.length === 0 ? (
						<p className="empty">No epic has cards left to do.</p>
					) : (
						<ul className="epic-bars">
							{epicsInFlight.map(({ epic, progress }) => (
								<li key={epic.id}>
									<Link href={`/epics?open=${epic.id}`} className="report-name">
										{epic.icon && <span className="record-icon">{epic.icon}</span>}
										{epic.name}
									</Link>
									<span className="report-status">{epic.status}</span>
									<ProgressMeter progress={progress} wide />
								</li>
							))}
						</ul>
					)}
				</div>

				<div className="report-card span-all">
					<h2>
						Needs attention <span className="count">{attention.length}</span>
					</h2>
					{attention.length === 0 ? (
						<p className="empty">Nothing is blocked, overrunning or sitting in a column for a week.</p>
					) : (
						<ul className="report-list attention">
							{attention.slice(0, ATTENTION).map(({ card, reasons }) => (
								<li key={card.id}>
									<span className={`dot phase-${phaseOf(card.status)}`} aria-hidden="true" />
									<span className="ident">{card.id}</span>
									<Link href={`/card/${card.id}`} className="report-name">
										{card.name}
									</Link>
									<span className="report-status">{card.status}</span>
									<span className="attention-reasons">
										{reasons.map((reason) => (
											<span key={reason.label} className={`pill ${reason.tone}`} title={reason.title}>
												{reason.label}
											</span>
										))}
									</span>
								</li>
							))}
						</ul>
					)}
					{attention.length > ATTENTION && (
						<p className="report-note more">
							{attention.length - ATTENTION} more - the board's Overrunning and Blocked filters and its Longest in
							column sort find the rest.
						</p>
					)}
				</div>
			</div>
		</section>
	);
}
