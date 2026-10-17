import { currentSprint, DAY, doneAt, timeOf } from "./metrics";
import type { Break, Card } from "./shared";

export const CONFIDENCES = ["On track", "At risk - plan in place", "At risk - no plan"] as const;

export type Confidence = (typeof CONFIDENCES)[number];

export const AVERAGE_SPEED_WEEKS = 6;
export const DEFAULT_AVERAGE_SPEED = 10;
export const DEFAULT_REFINEMENT_DAYS = 2;
export const PAST_DAYS = 730;
export const FUTURE_DAYS = 1826;

export function dayOf(text: string | null | undefined): number | null {
	const match = text?.match(/^(\d{4})-(\d{2})-(\d{2})/);
	if (!match) return null;
	return Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])) / DAY;
}

export function localDay(date: Date): number {
	return Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / DAY;
}

export function dayText(day: number): string {
	return new Date(day * DAY).toISOString().slice(0, 10);
}

export function mondayOf(day: number): number {
	return day - ((new Date(day * DAY).getUTCDay() + 6) % 7);
}

export type Off = [number, number];

export function daysOff(breaks: Pick<Break, "from" | "to" | "project">[], team: string | null): Off[] {
	const spans = breaks
		.filter((one) => one.project == null || one.project === team)
		.flatMap((one): Off[] => {
			const from = dayOf(one.from);
			const to = dayOf(one.to);
			return from != null && to != null && to >= from ? [[from, to]] : [];
		})
		.sort((a, b) => a[0] - b[0]);
	const merged: Off[] = [];
	for (const [from, to] of spans) {
		const last = merged.at(-1);
		if (last && from <= last[1] + 1) last[1] = Math.max(last[1], to);
		else merged.push([from, to]);
	}
	return merged;
}

export function isOff(day: number, off: Off[]): boolean {
	return off.some(([from, to]) => day >= from && day <= to);
}

function weekOff(monday: number, off: Off[]): boolean {
	return [0, 1, 2, 3, 4].every((weekday) => isOff(monday + weekday, off));
}

export function openFrom(day: number, off: Off[]): number {
	let open = day;
	for (const [from, to] of off) if (open >= from && open <= to) open = to + 1;
	return open;
}

export function afterOpen(day: number, count: number, off: Off[]): number {
	let open = day;
	let left = count;
	for (const [from, to] of off) {
		if (left <= 0) return open;
		if (to < open) continue;
		if (from > open) {
			const gap = from - open;
			if (gap >= left) return open + left;
			left -= gap;
		}
		open = Math.max(open, to + 1);
	}
	return open + Math.max(0, left);
}

export function openDays(first: number, last: number, off: Off[]): number {
	if (last < first) return 0;
	return off.reduce(
		(days, [from, to]) => days - Math.max(0, Math.min(to, last) - Math.max(from, first) + 1),
		last - first + 1,
	);
}

type Sized = Pick<Card, "status" | "complexity" | "estimate" | "type" | "dependent_on"> & Partial<Pick<Card, "blocked">>;

function splitParent(card: Pick<Sized, "dependent_on">) {
	return (card.dependent_on?.length ?? 0) > 0;
}

function positive(value: number | null | undefined): number | null {
	return value != null && value > 0 ? value : null;
}

export function pointsOf(card: Pick<Sized, "complexity" | "estimate" | "type">): number | null {
	if (card.type === "Timebox") return null;
	return positive(card.complexity) ?? positive(card.estimate);
}

export type AverageSpeed = {
	perWeek: number;
	source: "measured" | "sprint" | "default";
	points: number;
	weeks: number;
	tickets: number;
	uncounted: number;
	timeboxes: number;
	mondays: number[];
};

type Delivered = Sized & Pick<Card, "dates" | "moved">;

export function averageSpeedOf(
	cards: Delivered[],
	sprints: Pick<Card, "start" | "end" | "speed">[],
	now = new Date(),
	off: Off[] = [],
): AverageSpeed {
	const end = now.getTime();
	const finished = new Map<number, Delivered[]>();
	for (const card of cards) {
		if (splitParent(card)) continue;
		const at = doneAt(card);
		if (at == null || at > end) continue;
		const monday = mondayOf(localDay(new Date(at)));
		finished.set(monday, [...(finished.get(monday) ?? []), card]);
	}
	const mondays = [...finished.keys()]
		.filter((monday) => !weekOff(monday, off))
		.sort((a, b) => b - a)
		.slice(0, AVERAGE_SPEED_WEEKS);
	let points = 0;
	let tickets = 0;
	let uncounted = 0;
	let timeboxes = 0;
	for (const card of mondays.flatMap((monday) => finished.get(monday) ?? [])) {
		const complexity = card.type === "Timebox" ? null : positive(card.complexity);
		if (card.type === "Timebox") timeboxes += 1;
		else if (complexity == null) uncounted += 1;
		else {
			points += complexity;
			tickets += 1;
		}
	}
	const counts = { tickets, uncounted, timeboxes };
	if (points > 0) {
		return { perWeek: points / mondays.length, source: "measured", points, weeks: mondays.length, ...counts, mondays };
	}
	const speed = currentSprint(sprints, now)?.speed ?? 0;
	if (speed > 0) return { perWeek: speed * 5, source: "sprint", points: 0, weeks: 0, ...counts, mondays: [] };
	return { perWeek: DEFAULT_AVERAGE_SPEED, source: "default", points: 0, weeks: 0, ...counts, mondays: [] };
}

export type SprintDelivery = {
	points: number;
	tickets: number;
	uncounted: number;
	timeboxes: number;
	perWeek: number | null;
};

export function deliveredIn(
	sprint: Pick<Card, "id" | "start" | "end">,
	cards: (Sized & Pick<Card, "dates" | "moved" | "sprint">)[],
): SprintDelivery {
	const first = dayOf(sprint.start);
	const last = dayOf(sprint.end);
	const delivered: SprintDelivery = { points: 0, tickets: 0, uncounted: 0, timeboxes: 0, perWeek: null };
	if (first == null || last == null || last < first) return delivered;
	for (const card of cards) {
		if (card.sprint !== sprint.id || splitParent(card) || doneAt(card) == null) continue;
		const complexity = card.type === "Timebox" ? null : positive(card.complexity);
		if (card.type === "Timebox") delivered.timeboxes += 1;
		else if (complexity == null) delivered.uncounted += 1;
		else {
			delivered.points += complexity;
			delivered.tickets += 1;
		}
	}
	delivered.perWeek = Math.round((delivered.points / ((last - first + 1) / 7)) * 10) / 10;
	return delivered;
}

export type Remaining = {
	points: number;
	complexity: number;
	fromEstimate: number;
	estimate: number;
	open: number;
	tickets: number;
	sized: number;
	estimated: number;
	unsized: number;
	done: number;
	dropped: number;
};

export function remainingOf(cards: Sized[]): Remaining {
	const left: Remaining = {
		points: 0,
		complexity: 0,
		fromEstimate: 0,
		estimate: 0,
		open: 0,
		tickets: 0,
		sized: 0,
		estimated: 0,
		unsized: 0,
		done: 0,
		dropped: 0,
	};
	for (const card of cards) {
		if (card.status === "Deprioritised") left.dropped += 1;
		else if (splitParent(card)) continue;
		else if (card.status === "Done") left.done += 1;
		else {
			left.open += 1;
			if (card.type === "Timebox") continue;
			left.tickets += 1;
			const complexity = positive(card.complexity);
			const estimate = positive(card.estimate);
			if (complexity != null) {
				left.sized += 1;
				left.complexity += complexity;
			}
			if (estimate != null) {
				left.estimated += 1;
				left.estimate += estimate;
			}
			if (complexity == null && estimate != null) left.fromEstimate += estimate;
			if (complexity == null && estimate == null) left.unsized += 1;
		}
	}
	left.points = left.complexity + left.fromEstimate;
	return left;
}

export type Totals = { tickets: number; estimate: number; estimated: number; complexity: number; sized: number };

export type Estimates = { total: Totals; left: Remaining };

export function estimatesOf(cards: Sized[]): Estimates {
	const total: Totals = { tickets: 0, estimate: 0, estimated: 0, complexity: 0, sized: 0 };
	for (const card of cards) {
		if (card.status === "Deprioritised" || splitParent(card) || card.type === "Timebox") continue;
		total.tickets += 1;
		const complexity = positive(card.complexity);
		const estimate = positive(card.estimate);
		if (complexity != null) {
			total.sized += 1;
			total.complexity += complexity;
		}
		if (estimate != null) {
			total.estimated += 1;
			total.estimate += estimate;
		}
	}
	return { total, left: remainingOf(cards) };
}

type Planned = Pick<
	Card,
	"id" | "status" | "start" | "target" | "rank" | "confidence" | "dates" | "moved" | "project" | "track"
> &
	Partial<Pick<Card, "blocked">>;

export type Team = { tracks: number; perWeek: number };

export function teamOf(record: Pick<Card, "project">, known: Record<string, unknown>): string | null {
	return record.project && record.project in known ? record.project : null;
}

type Worked = Sized & Pick<Card, "epic" | "dates" | "moved">;

function startedAt(epic: Pick<Card, "dates">, all: Worked[]): number | null {
	const cards = all.filter((card) => card.type !== "Timebox");
	const stamps = [
		timeOf(epic.dates?.["Tickets In Dev"]),
		...cards.map((card) => timeOf(card.dates?.["In Dev"])),
		...cards.map((card) => doneAt(card)),
	].filter((time): time is number => time != null);
	return stamps.length > 0 ? Math.min(...stamps) : null;
}

export function inProgressOf(epic: Pick<Card, "status" | "dates">, cards: Worked[]): boolean {
	if (epic.status === "Epic Done") return false;
	if (epic.status === "Tickets In Dev") return true;
	return cards.some(
		(card) =>
			card.type !== "Timebox" &&
			card.status !== "Deprioritised" &&
			(card.status === "Done" || card.dates?.["In Dev"] != null),
	);
}

export function epicsInProgressOver(
	epics: Pick<Card, "id" | "status" | "dates" | "moved">[],
	cards: Worked[],
	from: number,
	to: number,
): number {
	if (to <= from) return 0;
	let covered = 0;
	for (const epic of epics) {
		const own = cards.filter((card) => card.epic === epic.id);
		const began = startedAt(epic, own);
		if (began == null) continue;
		const ended = doneAt(epic) ?? to;
		covered += Math.max(0, Math.min(ended, to) - Math.max(began, from));
	}
	return covered / (to - from);
}

export type TrackSpeed = {
	perWeek: number;
	source: "measured" | "overall";
	speed: AverageSpeed;
	inProgress: number;
};

function trackSpeedOf(
	speed: AverageSpeed,
	epics: Pick<Card, "id" | "status" | "dates" | "moved">[],
	cards: Worked[],
	now: Date,
	source: TrackSpeed["source"],
): TrackSpeed {
	const end = now.getTime();
	const weekly = speed.mondays.map((monday) =>
		epicsInProgressOver(epics, cards, monday * DAY, Math.min(end, (monday + 7) * DAY)),
	);
	const inProgress =
		speed.source === "measured" && weekly.length > 0 ? weekly.reduce((sum, one) => sum + one, 0) / weekly.length : 0;
	return {
		perWeek: speed.perWeek / Math.max(1, inProgress),
		source,
		speed,
		inProgress: Math.round(inProgress * 10) / 10,
	};
}

export function trackSpeedsOf(
	cards: Worked[],
	epics: Pick<Card, "id" | "status" | "dates" | "moved" | "project">[],
	projects: string[],
	sprints: Pick<Card, "start" | "end" | "speed">[],
	now = new Date(),
	breaks: Pick<Break, "from" | "to" | "project">[] = [],
): { overall: TrackSpeed; teams: Record<string, TrackSpeed> } {
	const known = Object.fromEntries(projects.map((id) => [id, true]));
	const overall = trackSpeedOf(
		averageSpeedOf(cards, sprints, now, daysOff(breaks, null)),
		epics,
		cards,
		now,
		"overall",
	);
	const teamOfEpic = Object.fromEntries(epics.map((epic) => [epic.id, teamOf(epic, known)]));
	const teamOfCard = (card: Worked & Pick<Card, "project">) =>
		card.epic && card.epic in teamOfEpic ? teamOfEpic[card.epic] : teamOf(card, known);
	const teams: Record<string, TrackSpeed> = {};
	for (const team of projects) {
		const own = cards.filter((card) => teamOfCard(card) === team);
		const speed = averageSpeedOf(own, [], now, daysOff(breaks, team));
		teams[team] =
			speed.source === "measured"
				? trackSpeedOf(
						speed,
						epics.filter((epic) => teamOfEpic[epic.id] === team),
						own,
						now,
						"measured",
					)
				: overall;
	}
	return { overall, teams };
}

function idNumber(id: string) {
	return Number(id.split("-").at(-1));
}

export function planOrder<T extends Pick<Card, "id" | "rank" | "target">>(epics: T[]): T[] {
	const last = Number.POSITIVE_INFINITY;
	return [...epics].sort(
		(a, b) =>
			(a.rank ?? last) - (b.rank ?? last) ||
			(dayOf(a.target) ?? last) - (dayOf(b.target) ?? last) ||
			idNumber(a.id) - idNumber(b.id),
	);
}

export function refinedAtOf(epic: Pick<Card, "dates">): number | null {
	return timeOf(epic.dates?.["Ready for Dev"]) ?? timeOf(epic.dates?.["Tickets In Dev"]);
}

export type Refinement = { days: number; source: "measured" | "default"; epics: number };

export function refinementOf(epics: Pick<Card, "start" | "dates">[]): Refinement {
	const spans = epics.flatMap((epic) => {
		const start = dayOf(epic.start);
		const at = refinedAtOf(epic);
		const end = at == null ? null : localDay(new Date(at));
		return start != null && end != null && end >= start ? [end - start] : [];
	});
	if (spans.length === 0) return { days: DEFAULT_REFINEMENT_DAYS, source: "default", epics: 0 };
	const days = Math.max(1, Math.round(spans.reduce((sum, span) => sum + span, 0) / spans.length));
	return { days, source: "measured", epics: spans.length };
}

export type Phase = "backlog" | "refinement" | "delivery" | "done";

export type Blocked = "epic" | "cards" | null;

export function openWorkOf<T extends Sized>(cards: T[]): T[] {
	return cards.filter(
		(card) =>
			card.type !== "Timebox" &&
			!splitParent(card) &&
			card.status !== "Done" &&
			card.status !== "Deprioritised",
	);
}

export function lateOf(
	target: number | null,
	remaining: Pick<Remaining, "open" | "done">,
	cards: Pick<Card, "status" | "dates" | "moved">[],
	today: number,
): number {
	if (target == null) return 0;
	if (remaining.open > 0) return Math.max(0, today - target);
	const finished = cards.map((card) => doneAt(card)).filter((at): at is number => at != null);
	if (remaining.done === 0 || finished.length === 0) return 0;
	return Math.max(0, localDay(new Date(Math.max(...finished))) - target);
}

export function blockedOf(epic: Pick<Card, "status"> & Partial<Pick<Card, "blocked">>, cards: Sized[]): Blocked {
	if (epic.status === "Epic Done") return null;
	if (epic.blocked) return "epic";
	const open = openWorkOf(cards);
	return open.length > 0 && open.every((card) => card.blocked) ? "cards" : null;
}

export type Row = {
	id: string;
	phase: Phase;
	refineStart: number | null;
	refineEnd: number | null;
	refineForecast: boolean;
	team: string;
	remaining: Remaining;
	done: boolean;
	doneDay: number | null;
	start: number | null;
	target: number | null;
	backwards: boolean;
	begin: number | null;
	projected: number | null;
	late: number;
	needed: number | null;
	atRisk: boolean;
	perWeek: number;
	inProgress: boolean;
	track: number | null;
	pin: number | null;
	pinIgnored: boolean;
	pausedUntil: number | null;
	blocked: Blocked;
};

export function planOf(
	epics: Planned[],
	cards: (Sized & Pick<Card, "epic"> & Partial<Pick<Card, "dates" | "moved">>)[],
	teams: Record<string, Team> | number,
	today: number,
	refinement: Refinement = { days: DEFAULT_REFINEMENT_DAYS, source: "default", epics: 0 },
	breaks: Pick<Break, "from" | "to" | "project">[] = [],
): Record<string, Row> {
	const rows: Record<string, Row> = {};
	const byEpic: Record<string, Worked[]> = {};
	for (const card of cards) if (card.epic) (byEpic[card.epic] ??= []).push(card);
	const known: Record<string, Team> = typeof teams === "number" ? { "": { tracks: 1, perWeek: teams } } : teams;
	const grouped: Record<string, Planned[]> = {};
	for (const epic of epics) {
		const team = typeof teams === "number" ? "" : teamOf(epic, known);
		if (team != null) (grouped[team] ??= []).push(epic);
	}
	for (const [team, members] of Object.entries(grouped)) {
		const { tracks: count, perWeek } = known[team];
		const off = daysOff(breaks, team === "" ? null : team);
		const tracks = Math.max(0, Math.floor(count));
		const perDay = Math.max(perWeek, 0.01) / 7;
		const free: number[] = Array.from({ length: tracks }, () => today);
		const ahead: number[] = Array.from({ length: tracks }, () => 0);
		const queue: Row[] = [];
		for (const epic of planOrder(members)) {
			const start = dayOf(epic.start);
			const target = dayOf(epic.target);
			const own = byEpic[epic.id] ?? [];
			const pin = epic.track != null && epic.track > 0 ? Math.floor(epic.track) : null;
			const inProgress = inProgressOf(epic, own);
			const refinedAt = refinedAtOf(epic) ?? (inProgress ? startedAt(epic, own) : null);
			const phase: Phase =
				epic.status === "Epic Done"
					? "done"
					: refinedAt != null || inProgress
						? "delivery"
						: epic.status === "Backlog"
							? "backlog"
							: "refinement";
			const row: Row = {
				id: epic.id,
				phase,
				refineStart: phase === "backlog" ? null : start,
				refineEnd: refinedAt == null ? null : localDay(new Date(refinedAt)),
				refineForecast: false,
				team,
				remaining: remainingOf(own),
				done: epic.status === "Epic Done",
				doneDay: null,
				start,
				target,
				backwards: start != null && target != null && start > target,
				begin: null,
				projected: null,
				late: 0,
				needed: null,
				atRisk: false,
				perWeek,
				inProgress,
				track: null,
				pin,
				pinIgnored: pin != null && pin > tracks,
				pausedUntil: null,
				blocked: blockedOf(epic, own),
			};
			rows[epic.id] = row;
			if (row.done) {
				const at = doneAt(epic);
				row.doneDay = at == null ? null : localDay(new Date(at));
				row.late = target != null && row.doneDay != null ? Math.max(0, row.doneDay - target) : 0;
			} else {
				row.late = lateOf(target, row.remaining, own, today);
				if (row.blocked == null && row.remaining.open === 0 && row.remaining.done > 0) {
					row.begin = today;
					row.projected = today;
				} else if (row.blocked == null && row.remaining.open > 0) {
					queue.push(row);
				}
			}
		}
		if (tracks === 0) continue;
		for (const row of Object.values(rows)) {
			if (row.team !== team || row.blocked != null || (row.phase !== "refinement" && row.phase !== "backlog")) continue;
			row.refineStart ??= openFrom(today, off);
			row.refineEnd = Math.max(today, afterOpen(row.refineStart, refinement.days, off));
			row.refineForecast = true;
		}
		const readyOf = (row: Row) => Math.max(today, row.phase === "delivery" ? today : (row.refineEnd ?? today));
		const laneOf = (row: Row) => (row.pin != null && !row.pinIgnored ? row.pin - 1 : null);
		const waiting = queue.filter((row) => row.remaining.points > 0);
		for (const row of queue) {
			if (row.remaining.points > 0) continue;
			row.begin = readyOf(row);
			row.track = row.pin != null && !row.pinIgnored ? row.pin : null;
		}
		let now = today;
		while (waiting.length > 0) {
			const wanted: number[] = Array.from({ length: tracks }, () => 0);
			for (const row of waiting) {
				const lane = laneOf(row);
				if (lane != null) wanted[lane] += 1;
			}
			for (const row of [...waiting]) {
				if (readyOf(row) > now) continue;
				const pinned = laneOf(row);
				const open = Array.from({ length: tracks }, (_, index) => index).filter(
					(index) => free[index] <= now && (pinned == null || index === pinned),
				);
				if (open.length === 0) continue;
				const lane = open.find((index) => wanted[index] === 0) ?? open[0];
				if (pinned != null) wanted[pinned] -= 1;
				waiting.splice(waiting.indexOf(row), 1);
				row.track = lane + 1;
				row.begin = openFrom(now, off);
				if (row.inProgress && now > today) row.pausedUntil = row.begin;
				const days = Math.ceil(row.remaining.points / perDay);
				const end = afterOpen(row.begin, days, off);
				row.projected = Math.max(row.begin, end - 1);
				free[lane] = end;
				ahead[lane] += row.remaining.points;
				row.late = row.target != null ? Math.max(0, row.projected - row.target) : 0;
				if (row.target != null) {
					const weeks = openDays(today, row.target, off) / 7;
					row.needed = weeks > 0 ? Math.round((ahead[lane] / weeks) * 10) / 10 : Number.POSITIVE_INFINITY;
				}
				const epic = members.find((one) => one.id === row.id);
				row.atRisk = row.late > 0 && (epic?.confidence == null || epic.confidence === "On track");
			}
			const next = [...free, ...waiting.map(readyOf)].filter((day) => day > now);
			if (next.length === 0) break;
			now = Math.min(...next);
		}
	}
	return rows;
}

export type Span = { first: number; last: number; clippedBefore: boolean; clippedAfter: boolean };

export function spanOf(days: (number | null | undefined)[], today: number): Span {
	const known = days.filter((day): day is number => day != null && Number.isFinite(day));
	const earliest = Math.min(today - 14, ...known);
	const latest = Math.max(today + 56, ...known) + 28;
	const first = mondayOf(Math.max(earliest, today - PAST_DAYS));
	const last = Math.min(latest, today + FUTURE_DAYS);
	return { first, last, clippedBefore: earliest < today - PAST_DAYS, clippedAfter: latest > today + FUTURE_DAYS };
}

export function lateText(days: number, done: boolean) {
	const count = days === 1 ? "1 day late" : `${days} days late`;
	return done ? `Delivered ${count}` : count;
}
