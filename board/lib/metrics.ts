import { CARD_COLUMNS, type Card, EPIC_COLUMNS, phaseOf } from "./shared";

const WALK = [...CARD_COLUMNS, ...EPIC_COLUMNS];

function walkIndex(column: string) {
	const index = WALK.indexOf(column);
	return index < 0 ? WALK.length : index;
}

const MINUTE = 60000;
const HOUR = 60 * MINUTE;
export const DAY = 24 * HOUR;

export function timeOf(stamp: string | null | undefined): number | null {
	if (!stamp) return null;
	const time = new Date(stamp).getTime();
	return Number.isNaN(time) ? null : time;
}

export function span(ms: number): string {
	const minutes = Math.round(ms / MINUTE);
	if (minutes < 1) return "<1m";
	if (minutes < 60) return `${minutes}m`;
	const hours = Math.floor(minutes / 60);
	const restMinutes = minutes % 60;
	if (hours < 24) return restMinutes ? `${hours}h ${restMinutes}m` : `${hours}h`;
	const days = Math.floor(hours / 24);
	const restHours = hours % 24;
	if (days < 10 && restHours) return `${days}d ${restHours}h`;
	return `${Math.round(minutes / 60 / 24)}d`;
}

export type Stage = { column: string; at: string | null; ms: number | null; current: boolean };

type Dated = Pick<Card, "dates" | "status" | "moved" | "created">;

type Entry = { column: string; at: string | null; time: number | null };

export function stagesOf(record: Dated, now = Date.now()): Stage[] {
	const entries: Entry[] = Object.entries(record.dates ?? {})
		.map(([column, at]) => ({ column, at, time: timeOf(at) }))
		.filter((entry): entry is { column: string; at: string; time: number } => entry.time != null)
		.sort((a, b) => a.time - b.time || walkIndex(a.column) - walkIndex(b.column));
	const last = entries.at(-1);
	const moved = timeOf(record.moved);
	if (record.status && last?.column !== record.status && (last || moved != null)) {
		const known = moved != null && (last?.time == null || moved >= last.time);
		entries.push({ column: record.status, at: known ? (record.moved ?? null) : null, time: known ? moved : null });
	}
	const finished = phaseOf(record.status) === "done";
	return entries.map((entry, index) => {
		const next = entries[index + 1];
		if (next) {
			const ms = next.time != null && entry.time != null ? Math.max(0, next.time - entry.time) : null;
			return { column: entry.column, at: entry.at, ms, current: false };
		}
		if (finished) return { column: entry.column, at: entry.at, ms: null, current: false };
		return {
			column: entry.column,
			at: entry.at,
			ms: entry.time == null ? null : Math.max(0, now - entry.time),
			current: true,
		};
	});
}

const DONE_COLUMNS = ["Done", "Epic Done"];
const START_COLUMNS = ["In Dev", "Tickets In Dev"];

export function doneAt(record: Pick<Card, "dates" | "status" | "moved">): number | null {
	if (!DONE_COLUMNS.includes(record.status)) return null;
	const stamps = [timeOf(record.dates?.[record.status]), timeOf(record.moved)].filter((time) => time != null);
	return stamps.length > 0 ? Math.max(...stamps) : null;
}

export type Flow = { lead: number | null; cycle: number | null; age: number | null };

export function flowOf(record: Dated, now = Date.now()): Flow {
	const created = timeOf(record.created);
	const done = doneAt(record);
	const started = START_COLUMNS.map((column) => timeOf(record.dates?.[column])).find((time) => time != null) ?? null;
	const end = done ?? now;
	return {
		lead: done != null && created != null ? Math.max(0, done - created) : null,
		cycle: started != null ? Math.max(0, end - started) : null,
		age: done == null && created != null ? Math.max(0, now - created) : null,
	};
}

export type Progress = {
	total: number;
	done: number;
	dropped: number;
	points: number;
	donePoints: number;
	unsized: number;
};

export function progressOf(cards: Pick<Card, "status" | "complexity">[]): Progress {
	const progress: Progress = { total: 0, done: 0, dropped: 0, points: 0, donePoints: 0, unsized: 0 };
	for (const card of cards) {
		if (card.status === "Deprioritised") {
			progress.dropped += 1;
			continue;
		}
		const points = card.complexity ?? 0;
		progress.total += 1;
		progress.points += points;
		if (phaseOf(card.status) === "done") {
			progress.done += 1;
			progress.donePoints += points;
		} else if (card.complexity == null) {
			progress.unsized += 1;
		}
	}
	return progress;
}

export function byPoints(progress: Progress): boolean {
	return progress.points > 0 && progress.unsized === 0;
}

export function progressShare(progress: Progress): number {
	if (byPoints(progress)) return progress.donePoints / progress.points;
	return progress.total > 0 ? progress.done / progress.total : 0;
}

export function progressTitle(progress: Progress): string {
	const parts = [`${progress.done} of ${progress.total} cards done`];
	if (progress.points > 0) parts.push(`${progress.donePoints} of ${progress.points} points`);
	if (progress.points > 0 && progress.unsized > 0)
		parts.push(`${progress.unsized} open ${progress.unsized === 1 ? "card has" : "cards have"} no points, so the bar counts cards`);
	if (progress.dropped > 0) parts.push(`${progress.dropped} deprioritised and left out`);
	return parts.join(", ");
}

function localDay(day: string): Date | null {
	const match = day.match(/^(\d{4})-(\d{2})-(\d{2})/);
	return match ? new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3])) : null;
}

function dayText(date: Date) {
	return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

const LONGEST_SPRINT = 92;

export function sprintDays(start: string | null | undefined, end: string | null | undefined): string[] {
	const first = localDay(start ?? "");
	const last = localDay(end ?? "");
	if (!first || !last || last < first) return [];
	const days: string[] = [];
	for (let day = first, count = 0; day <= last && count < LONGEST_SPRINT; count += 1) {
		if (day.getDay() !== 0 && day.getDay() !== 6) days.push(dayText(day));
		day = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1);
	}
	return days;
}

export type Measure = "points" | "cards";

export type Burndown = {
	days: string[];
	total: number;
	ideal: number[];
	remaining: (number | null)[];
};

type Burnable = Pick<Card, "status" | "complexity" | "dates" | "moved">;

export function burndownOf(
	sprint: { start?: string | null; end?: string | null },
	cards: Burnable[],
	measure: Measure,
	now = Date.now(),
): Burndown {
	const days = sprintDays(sprint.start, sprint.end);
	const weight = (card: Burnable) => (measure === "points" ? (card.complexity ?? 0) : 1);
	const counted = cards.filter((card) => card.status !== "Deprioritised");
	const total = counted.reduce((sum, card) => sum + weight(card), 0);
	const finished = counted.map((card) => ({ weight: weight(card), at: doneAt(card) }));
	const left = (at: number) =>
		finished.reduce((sum, card) => (card.at != null && card.at <= at ? sum : sum + card.weight), 0);
	const startOf = (day: string) => localDay(day)?.getTime() ?? 0;
	const endOf = (day: string) => {
		const date = localDay(day) ?? new Date(0);
		return new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1).getTime();
	};
	const steps = days.length;
	const ideal = Array.from({ length: steps + 1 }, (_, index) =>
		steps === 0 ? total : Math.round(total * (1 - index / steps) * 100) / 100,
	);
	const remaining = Array.from({ length: steps + 1 }, (_, index) => {
		if (steps === 0) return null;
		const opened = index === 0 ? startOf(days[0]) : startOf(days[index - 1]);
		if (opened > now) return null;
		const at = index === 0 ? startOf(days[0]) : Math.min(endOf(days[index - 1]), now);
		return left(at);
	});
	return { days, total, ideal, remaining };
}

export function currentSprint<T extends { start?: string | null; end?: string | null }>(
	sprints: T[],
	now = new Date(),
): T | null {
	const today = dayText(now);
	const running = sprints.find((sprint) => (sprint.start ?? "") <= today && today <= (sprint.end ?? ""));
	if (running) return running;
	const started = sprints
		.filter((sprint) => sprint.start && sprint.start <= today)
		.sort((a, b) => (b.start ?? "").localeCompare(a.start ?? ""));
	return started[0] ?? sprints[0] ?? null;
}

export type Week = { start: string; done: number; points: number };

export function throughputOf(
	cards: Pick<Card, "status" | "complexity" | "dates" | "moved">[],
	weeks: number,
	now = new Date(),
): Week[] {
	const monday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - ((now.getDay() + 6) % 7));
	const starts = Array.from(
		{ length: weeks },
		(_, index) => new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() - 7 * (weeks - 1 - index)),
	);
	const result = starts.map((start) => ({ start: dayText(start), done: 0, points: 0 }));
	for (const card of cards) {
		const at = doneAt(card);
		if (at == null) continue;
		const index = starts.findLastIndex((start) => start.getTime() <= at);
		if (index < 0 || at > now.getTime()) continue;
		result[index].done += 1;
		result[index].points += card.complexity ?? 0;
	}
	return result;
}

export function median(values: number[]): number | null {
	if (values.length === 0) return null;
	const sorted = [...values].sort((a, b) => a - b);
	const middle = Math.floor(sorted.length / 2);
	return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}
