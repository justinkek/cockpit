import { currentSprint, DAY, doneAt, timeOf } from "./metrics";
import type { Card } from "./shared";

export const CONFIDENCES = ["On track", "At risk - plan in place", "At risk - no plan"] as const;

export type Confidence = (typeof CONFIDENCES)[number];

export const AVERAGE_SPEED_WEEKS = 6;
export const DEFAULT_AVERAGE_SPEED = 10;
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

type Sized = Pick<Card, "status" | "complexity" | "estimate" | "type" | "dependent_on">;

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
};

type Delivered = Sized & Pick<Card, "dates" | "moved">;

export function averageSpeedOf(
	cards: Delivered[],
	sprints: Pick<Card, "start" | "end" | "speed">[],
	now = new Date(),
): AverageSpeed {
	const end = now.getTime();
	const windowStart = end - AVERAGE_SPEED_WEEKS * 7 * DAY;
	let first = Number.POSITIVE_INFINITY;
	let points = 0;
	let tickets = 0;
	let uncounted = 0;
	let timeboxes = 0;
	for (const card of cards) {
		if (splitParent(card)) continue;
		const at = doneAt(card);
		if (at == null || at > end) continue;
		first = Math.min(first, at);
		if (at < windowStart) continue;
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
		const weeks = Math.min(AVERAGE_SPEED_WEEKS, Math.max(1, (end - Math.max(windowStart, first)) / (7 * DAY)));
		return { perWeek: points / weeks, source: "measured", points, weeks: Math.round(weeks * 10) / 10, ...counts };
	}
	const speed = currentSprint(sprints, now)?.speed ?? 0;
	if (speed > 0) return { perWeek: speed * 5, source: "sprint", points: 0, weeks: 0, ...counts };
	return { perWeek: DEFAULT_AVERAGE_SPEED, source: "default", points: 0, weeks: 0, ...counts };
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

type Planned = Pick<
	Card,
	"id" | "status" | "start" | "target" | "rank" | "confidence" | "dates" | "moved" | "project" | "track"
>;

export const NO_PROJECT = "";

export type Team = { tracks: number; perWeek: number };

export function teamOf(record: Pick<Card, "project">, known: Record<string, unknown>): string {
	return record.project && record.project in known ? record.project : NO_PROJECT;
}

type Worked = Sized & Pick<Card, "epic" | "dates" | "moved">;

function startedAt(epic: Pick<Card, "dates">, cards: Worked[]): number | null {
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
		(card) => card.status !== "Deprioritised" && (card.status === "Done" || card.dates?.["In Dev"] != null),
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
	const inProgress =
		speed.source === "measured" ? epicsInProgressOver(epics, cards, end - speed.weeks * 7 * DAY, end) : 0;
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
): { overall: TrackSpeed; teams: Record<string, TrackSpeed> } {
	const known = Object.fromEntries(projects.map((id) => [id, true]));
	const overall = trackSpeedOf(averageSpeedOf(cards, sprints, now), epics, cards, now, "overall");
	const teamOfEpic = Object.fromEntries(epics.map((epic) => [epic.id, teamOf(epic, known)]));
	const teamOfCard = (card: Worked & Pick<Card, "project">) =>
		card.epic && card.epic in teamOfEpic ? teamOfEpic[card.epic] : teamOf(card, known);
	const teams: Record<string, TrackSpeed> = {};
	for (const team of [...projects, NO_PROJECT]) {
		const own = cards.filter((card) => teamOfCard(card) === team);
		const speed = averageSpeedOf(own, [], now);
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

export type Row = {
	id: string;
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
};

export function planOf(
	epics: Planned[],
	cards: (Sized & Pick<Card, "epic"> & Partial<Pick<Card, "dates" | "moved">>)[],
	teams: Record<string, Team> | number,
	today: number,
): Record<string, Row> {
	const rows: Record<string, Row> = {};
	const byEpic: Record<string, Worked[]> = {};
	for (const card of cards) if (card.epic) (byEpic[card.epic] ??= []).push(card);
	const known: Record<string, Team> = typeof teams === "number" ? {} : teams;
	const fallback: Team =
		typeof teams === "number"
			? { tracks: 1, perWeek: teams }
			: (teams[NO_PROJECT] ?? { tracks: 1, perWeek: DEFAULT_AVERAGE_SPEED });
	const grouped: Record<string, Planned[]> = {};
	for (const epic of epics) (grouped[teamOf(epic, known)] ??= []).push(epic);
	for (const [team, members] of Object.entries(grouped)) {
		const { tracks: count, perWeek } = team in known ? known[team] : fallback;
		const tracks = Math.max(1, Math.floor(count));
		const perDay = Math.max(perWeek, 0.01) / 7;
		const free: number[] = Array.from({ length: tracks }, () => today);
		const ahead: number[] = Array.from({ length: tracks }, () => 0);
		const queue: Row[] = [];
		for (const epic of planOrder(members)) {
			const start = dayOf(epic.start);
			const target = dayOf(epic.target);
			const own = byEpic[epic.id] ?? [];
			const pin = epic.track != null && epic.track > 0 ? Math.floor(epic.track) : null;
			const row: Row = {
				id: epic.id,
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
				inProgress: inProgressOf(epic, own),
				track: null,
				pin,
				pinIgnored: pin != null && pin > tracks,
				pausedUntil: null,
			};
			rows[epic.id] = row;
			if (row.done) {
				const at = doneAt(epic);
				row.doneDay = at == null ? null : localDay(new Date(at));
				row.late = target != null && row.doneDay != null ? Math.max(0, row.doneDay - target) : 0;
			} else if (row.remaining.open === 0 && row.remaining.done > 0) {
				row.begin = today;
				row.projected = today;
			} else if (row.remaining.open > 0) {
				queue.push(row);
			}
		}
		const order = [...queue.filter((row) => row.inProgress), ...queue.filter((row) => !row.inProgress)];
		const wanted: number[] = Array.from({ length: tracks }, () => 0);
		const want = (started: boolean) => {
			for (const row of order) {
				if (row.inProgress === started && row.pin != null && !row.pinIgnored) wanted[row.pin - 1] += 1;
			}
		};
		want(true);
		let waiting = false;
		for (const row of order) {
			if (!row.inProgress && !waiting) {
				waiting = true;
				want(false);
			}
			const pinned = row.pin != null && !row.pinIgnored;
			if (pinned) wanted[(row.pin ?? 1) - 1] -= 1;
			let lane = pinned ? (row.pin ?? 1) - 1 : 0;
			if (!pinned) {
				for (let index = 1; index < tracks; index += 1) {
					const better =
						free[index] < free[lane] || (free[index] === free[lane] && wanted[lane] > 0 && wanted[index] === 0);
					if (better) lane = index;
				}
			}
			row.track = lane + 1;
			row.begin = Math.max(free[lane], row.start ?? free[lane]);
			if (row.remaining.points === 0) continue;
			if (row.inProgress && row.begin > Math.max(today, row.start ?? today)) row.pausedUntil = row.begin;
			const days = Math.ceil(row.remaining.points / perDay);
			row.projected = row.begin + Math.max(0, days - 1);
			free[lane] = row.begin + days;
			ahead[lane] += row.remaining.points;
			row.late = row.target != null ? Math.max(0, row.projected - row.target) : 0;
			if (row.target != null) {
				const weeks = (row.target - today + 1) / 7;
				row.needed = weeks > 0 ? Math.round((ahead[lane] / weeks) * 10) / 10 : Number.POSITIVE_INFINITY;
			}
			const epic = members.find((one) => one.id === row.id);
			row.atRisk = row.late > 0 && (epic?.confidence == null || epic.confidence === "On track");
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
