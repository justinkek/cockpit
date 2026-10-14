export const CARD_COLUMNS = [
	"Backlog",
	"Ready for BR by AI",
	"In BR by AI",
	"Ready for BR",
	"In BR",
	"Ready for TR by AI",
	"In TR by AI",
	"Ready for TR",
	"In TR",
	"Ready for Sprint",
	"Sprint Backlog",
	"Daily Plan",
	"In Dev",
	"In CR by AI",
	"Ready for CR",
	"In CR",
	"Ready for FR",
	"In FR",
	"Ready for Validation",
	"Done",
];

export const CARD_PARKED = ["Deprioritised"];

export const CARD_BOARD_COLUMNS = [...CARD_COLUMNS.slice(0, -1), ...CARD_PARKED, "Done"];

export const EPIC_COLUMNS = [
	"Ready for FD by AI",
	"In FD by AI",
	"Ready for FD",
	"In FD",
	"Ready for TD by AI",
	"In TD by AI",
	"Ready for TD",
	"In TD",
	"Ready for Ticket Breakdown by AI",
	"In Ticket Breakdown by AI",
	"Ready for Ticket Breakdown",
	"In Ticket Breakdown",
	"Tickets In Dev",
	"Epic Done",
];

export type Kind = "card" | "epic";

export function boardColumns(kind: Kind) {
	return kind === "epic" ? EPIC_COLUMNS : CARD_BOARD_COLUMNS;
}

export const FIBONACCI = [0, 1, 2, 3, 5, 8, 13, 21, 34];

export type Card = {
	id: string;
	name: string;
	icon?: string | null;
	type?: "Feature" | "Bug" | "Timebox";
	status: string;
	epic?: string | null;
	project?: string | null;
	sprint?: string | null;
	due?: string | null;
	blocked?: string | null;
	dependent_on?: string[];
	dependency_for?: string[];
	complexity?: number | null;
	timebox_mins?: number | null;
	session?: string | null;
	claimed_at?: string | null;
	prs?: string | null;
	cost_usd?: number | null;
	tokens_k?: number | null;
	created: string;
	moved?: string;
	updated?: string;
	rank?: number | null;
	models?: Record<string, string>;
	back_from?: Record<string, number>;
	dates?: Record<string, string>;
	start?: string | null;
	end?: string | null;
	days_in_column?: number;
	overrunning?: boolean;
	body: string;
};

export type Stub = Card;

export type CommentThread = {
	thread: string;
	anchor: string | null;
	resolved?: boolean;
	comments: { id: string; author: string; at: string; text: string }[];
};

export type Named = { id: string; name: string };

export type Sprint = Named & { start?: string | null; end?: string | null };

export const TYPES = ["Feature", "Bug", "Timebox"] as const;

export function kindOf(id: string): Kind | null {
	if (/^(FEAT|BUG|TIME)-/.test(id)) return "card";
	if (id.startsWith("EPIC-")) return "epic";
	return null;
}

export function phaseOf(column: string): string {
	if (column === "Backlog" || column === "Deprioritised") return "idle";
	if (/\b(BR|TR|FD|TD)\b/.test(column) || column.includes("Ticket Breakdown")) return "refine";
	if (["Ready for Sprint", "Sprint Backlog", "Daily Plan"].includes(column)) return "planned";
	if (column === "In Dev" || column === "Tickets In Dev") return "dev";
	if (/\b(CR|FR)\b/.test(column)) return "review";
	if (column === "Ready for Validation") return "validate";
	if (column === "Done" || column === "Epic Done") return "done";
	return "idle";
}

const FIELD_NAMES: Record<string, string> = { timebox_mins: "timebox", prs: "PRs", due: "due date" };

export function fieldName(field: string) {
	return FIELD_NAMES[field] ?? field;
}

export type DueState = { tone: "overdue" | "soon" | "later"; label: string; title: string };

function localDay(date: Date) {
	return Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86400000;
}

export function dueState(record: Pick<Card, "due" | "status">, now = new Date()): DueState | null {
	const day = record.due?.match(/^(\d{4})-(\d{2})-(\d{2})/);
	if (!day) return null;
	const due = new Date(Number(day[1]), Number(day[2]) - 1, Number(day[3]));
	const days = localDay(due) - localDay(now);
	const finished = phaseOf(record.status) === "done" || record.status === "Deprioritised";
	const date = due.toLocaleDateString(undefined, { day: "numeric", month: "short" });
	const title = `Due ${due.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long", year: "numeric" })}`;
	if (finished) return { tone: "later", label: date, title };
	if (days < 0) return { tone: "overdue", label: days === -1 ? "Overdue 1 day" : `Overdue ${-days} days`, title };
	if (days === 0) return { tone: "soon", label: "Due today", title };
	if (days === 1) return { tone: "soon", label: "Due tomorrow", title };
	if (days <= 3) return { tone: "soon", label: `Due ${due.toLocaleDateString(undefined, { weekday: "short" })}`, title };
	return { tone: "later", label: `Due ${date}`, title };
}

export const SPLIT_ABOVE = 5;

export function bounces(record: Pick<Card, "back_from">) {
	return Object.entries(record.back_from ?? {}).filter(([, count]) => count > 0);
}

export function overrunTitle(record: Pick<Card, "type" | "timebox_mins" | "complexity">) {
	return record.type === "Timebox" && record.timebox_mins
		? `Its dev time has run past its ${record.timebox_mins}-minute timebox`
		: `Its dev time has run past ${record.complexity ?? 0} points of working time`;
}

export function manualRank(record: Pick<Card, "id" | "rank">) {
	return record.rank ?? -Number(record.id.split("-").at(-1));
}
