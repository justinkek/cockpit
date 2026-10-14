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

export type Stage = { column: string; at: string; ms: number | null; current: boolean };

type Dated = Pick<Card, "dates" | "status" | "moved" | "created">;

export function stagesOf(record: Dated, now = Date.now()): Stage[] {
	const entries = Object.entries(record.dates ?? {})
		.map(([column, at]) => ({ column, at, time: timeOf(at) }))
		.filter((entry): entry is { column: string; at: string; time: number } => entry.time != null)
		.sort((a, b) => a.time - b.time || walkIndex(a.column) - walkIndex(b.column));
	const finished = phaseOf(record.status) === "done";
	const moved = timeOf(record.moved);
	return entries.map((entry, index) => {
		const next = entries[index + 1];
		if (next) return { column: entry.column, at: entry.at, ms: Math.max(0, next.time - entry.time), current: false };
		if (finished && phaseOf(entry.column) === "done")
			return { column: entry.column, at: entry.at, ms: null, current: false };
		if (entry.column === record.status)
			return { column: entry.column, at: entry.at, ms: Math.max(0, now - entry.time), current: true };
		const end = moved != null && moved > entry.time ? moved : null;
		return { column: entry.column, at: entry.at, ms: end == null ? null : end - entry.time, current: false };
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
