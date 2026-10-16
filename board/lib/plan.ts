import { currentSprint, doneAt, median } from "./metrics";
import type { Card } from "./shared";

export const CONFIDENCES = ["On track", "At risk - plan in place", "At risk - no plan"] as const;

export type Confidence = (typeof CONFIDENCES)[number];

export const AVERAGE_SPEED_WEEKS = 6;
export const DEFAULT_AVERAGE_SPEED = 10;
export const DEFAULT_SIZE = 3;
export const PAST_DAYS = 730;
export const FUTURE_DAYS = 1826;

const DAY = 86400000;

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

type Sized = Pick<Card, "status" | "complexity" | "dependent_on">;

function splitParent(card: Sized) {
	return (card.dependent_on?.length ?? 0) > 0;
}

export type Size = { points: number; measured: boolean };

export function cardSizeOf(cards: Sized[]): Size {
	const sizes = cards
		.filter((card) => !splitParent(card) && (card.complexity ?? 0) > 0)
		.map((card) => card.complexity as number);
	const middle = median(sizes);
	return middle == null ? { points: DEFAULT_SIZE, measured: false } : { points: middle, measured: true };
}

export type AverageSpeed = { perWeek: number; source: "measured" | "sprint" | "default"; points: number; weeks: number };

type Delivered = Sized & Pick<Card, "dates" | "moved">;

export function averageSpeedOf(
	cards: Delivered[],
	sprints: Pick<Card, "start" | "end" | "speed">[],
	size: number,
	now = new Date(),
): AverageSpeed {
	const end = now.getTime();
	const windowStart = end - AVERAGE_SPEED_WEEKS * 7 * DAY;
	let first = Number.POSITIVE_INFINITY;
	let points = 0;
	for (const card of cards) {
		if (splitParent(card)) continue;
		const at = doneAt(card);
		if (at == null || at > end) continue;
		first = Math.min(first, at);
		if (at >= windowStart) points += card.complexity ?? size;
	}
	if (points > 0) {
		const weeks = Math.min(AVERAGE_SPEED_WEEKS, Math.max(1, (end - Math.max(windowStart, first)) / (7 * DAY)));
		return { perWeek: points / weeks, source: "measured", points, weeks: Math.round(weeks * 10) / 10 };
	}
	const speed = currentSprint(sprints, now)?.speed ?? 0;
	if (speed > 0) return { perWeek: speed * 5, source: "sprint", points: 0, weeks: 0 };
	return { perWeek: DEFAULT_AVERAGE_SPEED, source: "default", points: 0, weeks: 0 };
}

export type Remaining = { points: number; open: number; unsized: number; done: number; dropped: number };

export function remainingOf(cards: Sized[], size: number): Remaining {
	const left: Remaining = { points: 0, open: 0, unsized: 0, done: 0, dropped: 0 };
	for (const card of cards) {
		if (card.status === "Deprioritised") left.dropped += 1;
		else if (splitParent(card)) continue;
		else if (card.status === "Done") left.done += 1;
		else {
			left.open += 1;
			left.points += card.complexity ?? size;
			if (card.complexity == null) left.unsized += 1;
		}
	}
	return left;
}

type Planned = Pick<Card, "id" | "status" | "start" | "target" | "plan_rank" | "confidence" | "dates" | "moved">;

function idNumber(id: string) {
	return Number(id.split("-").at(-1));
}

export function planOrder<T extends Pick<Card, "id" | "plan_rank" | "target">>(epics: T[]): T[] {
	const last = Number.POSITIVE_INFINITY;
	return [...epics].sort(
		(a, b) =>
			(a.plan_rank ?? last) - (b.plan_rank ?? last) ||
			(dayOf(a.target) ?? last) - (dayOf(b.target) ?? last) ||
			idNumber(a.id) - idNumber(b.id),
	);
}

export type Row = {
	id: string;
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
};

export function planOf(
	epics: Planned[],
	cards: (Sized & Pick<Card, "epic">)[],
	averageSpeed: number,
	size: number,
	today: number,
): Record<string, Row> {
	const rows: Record<string, Row> = {};
	const byEpic: Record<string, Sized[]> = {};
	for (const card of cards) if (card.epic) (byEpic[card.epic] ??= []).push(card);
	const perDay = Math.max(averageSpeed, 0.01) / 7;
	let cursor = today;
	let ahead = 0;
	for (const epic of planOrder(epics)) {
		const start = dayOf(epic.start);
		const target = dayOf(epic.target);
		const remaining = remainingOf(byEpic[epic.id] ?? [], size);
		const row: Row = {
			id: epic.id,
			remaining,
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
		};
		if (row.done) {
			const at = doneAt(epic);
			row.doneDay = at == null ? null : localDay(new Date(at));
			row.late = target != null && row.doneDay != null ? Math.max(0, row.doneDay - target) : 0;
		} else if (remaining.open === 0 && remaining.done > 0) {
			row.begin = today;
			row.projected = today;
		} else if (remaining.open > 0) {
			row.begin = Math.max(cursor, start ?? cursor);
			const days = Math.ceil(remaining.points / perDay);
			row.projected = row.begin + Math.max(0, days - 1);
			cursor = row.begin + days;
			ahead += remaining.points;
			row.late = target != null ? Math.max(0, row.projected - target) : 0;
			if (target != null && remaining.points > 0) {
				const weeks = (target - today + 1) / 7;
				row.needed = weeks > 0 ? Math.round((ahead / weeks) * 10) / 10 : Number.POSITIVE_INFINITY;
			}
			row.atRisk = row.late > 0 && (epic.confidence == null || epic.confidence === "On track");
		}
		rows[epic.id] = row;
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
