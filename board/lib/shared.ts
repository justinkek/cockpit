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
	"Backlog",
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
	"Ready for Dev",
	"Tickets In Dev",
	"Epic Done",
];

export type Kind = "card" | "epic";

export type RecordKind = Kind | "project" | "sprint" | "reference" | "milestone";

export const PROJECT_STATUSES = ["Not started", "In progress", "Done"] as const;

export const DOMAINS = ["Tech", "Bizdev"] as const;

export function boardColumns(kind: Kind) {
	return kind === "epic" ? EPIC_COLUMNS : CARD_BOARD_COLUMNS;
}

export const FIBONACCI = [0, 1, 2, 3, 5, 8, 13, 21, 34];

export const TIMEBOXES = [15, 30, 45, 60, 90, 120, 180, 240];

export function timeboxText(minutes: number) {
	if (minutes < 60 || minutes % 60 !== 0) return `${minutes} min`;
	return minutes === 60 ? "1 hour" : `${minutes / 60} hours`;
}

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
	due_from?: string | null;
	urgent?: boolean;
	labels?: string[];
	blocked?: string | null;
	blocked_spans?: { from: string; to?: string }[];
	dependent_on?: string[];
	dependency_for?: string[];
	complexity?: number | null;
	estimate?: number | null;
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
	dev_days?: number | null;
	speed?: number | null;
	priority?: number | null;
	repo?: string | null;
	points?: number | null;
	why?: string | null;
	description?: string | null;
	domain?: string | null;
	stack?: string | null;
	card?: string | null;
	target?: string | null;
	confidence?: string | null;
	learning?: string | null;
	tracks?: number | null;
	track?: number | null;
	date?: string | null;
	days_in_column?: number;
	overrunning?: boolean;
	comments?: number;
	body: string;
};

export type Stub = Card;

export type HistoryChange = { field: string; from: unknown; to: unknown };

export type HistoryComment = {
	action: "added" | "resolved" | "reopened" | "edited" | "deleted" | "removed";
	id: string;
	thread: string;
	author: string;
	text: string;
};

export type HistoryEntry = {
	commit: string;
	at: string;
	author: string;
	subject: string;
	id: string;
	session: string | null;
	by: string | null;
	created: boolean;
	changes: HistoryChange[];
	body: { from: string; to: string } | null;
	comments: HistoryComment[];
	attachments: { action: "added" | "removed"; name: string }[];
};

export type CommentThread = {
	thread: string;
	anchor: string | null;
	resolved?: boolean;
	comments: { id: string; author: string; at: string; text: string; edited?: string }[];
};

export type InboxItem = {
	kind: "comment" | "waiting" | "blocked";
	id: string;
	name: string;
	status: string;
	at: string;
	unread: boolean;
	author?: string;
	text?: string;
	thread?: string;
	comment?: string;
	anchor?: string | null;
	resolved?: boolean;
};

export type Inbox = { me: string; seen: string | null; now: string; unread: number; items: InboxItem[] };

export type Named = { id: string; name: string };

export type SavedView = { name: string; kind: Kind; view: Record<string, unknown> };

export type Break = { id: string; from: string; to: string; name: string | null };

export type Sprint = Named & { start?: string | null; end?: string | null };

export const TYPES = ["Feature", "Bug", "Timebox"] as const;

export function kindOf(id: string): Kind | null {
	if (/^(FEAT|BUG|TIME)-/.test(id)) return "card";
	if (id.startsWith("EPIC-")) return "epic";
	return null;
}

const RECORD_KINDS: Record<string, RecordKind> = { PRJ: "project", SPR: "sprint", REF: "reference", MS: "milestone" };

export function recordKindOf(id: string): RecordKind | null {
	return kindOf(id) ?? RECORD_KINDS[id.split("-")[0]] ?? null;
}

export function homeOf(id: string): string {
	const kind = recordKindOf(id);
	if (kind === "epic") return `/epics?open=${id}`;
	if (kind === "project") return "/projects";
	if (kind === "sprint") return `/obeya?sprint=${id}#sprint`;
	if (kind === "reference") return "/references";
	if (kind === "milestone") return "/plan";
	return `/?open=${id}`;
}

export function kindName(kind: RecordKind) {
	return kind === "card" ? "ticket" : kind;
}

export function contentSearchFailed(kind: Kind, error: string) {
	return `Only the names and ids of the ${kindName(kind)}s were searched, because their content could not be: ${error}`;
}

export function phaseOf(column: string): string {
	if (column === "Backlog" || column === "Deprioritised") return "idle";
	if (/\b(BR|TR|FD|TD)\b/.test(column) || column.includes("Ticket Breakdown")) return "refine";
	if (["Ready for Sprint", "Sprint Backlog", "Daily Plan", "Ready for Dev"].includes(column)) return "planned";
	if (column === "In Dev" || column === "Tickets In Dev") return "dev";
	if (/\b(CR|FR)\b/.test(column)) return "review";
	if (column === "Ready for Validation") return "validate";
	if (column === "Done" || column === "Epic Done") return "done";
	return "idle";
}

const FIELD_NAMES: Record<string, string> = {
	timebox_mins: "timebox",
	prs: "PRs",
	due: "due date",
	start: "start date",
	target: "target date",
	urgent: "urgent flag",
	card: "ticket",
};

export const MODEL_STAGES = ["BR", "TR", "Dev", "CR"] as const;

export function fieldName(field: string) {
	if (field.startsWith("models.")) return `${field.slice(7)} model`;
	return FIELD_NAMES[field] ?? field;
}

export type DueState = { tone: "overdue" | "soon" | "later"; label: string; title: string; held: string | null };

function localDay(date: Date) {
	return Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86400000;
}

export function dueState(record: Pick<Card, "due" | "status" | "due_from">, now = new Date()): DueState | null {
	const state = dueOf(record, now);
	if (!state || !record.due_from) return state;
	return { ...state, title: `${state.title} - held to the target of ${record.due_from}`, held: record.due_from };
}

function dueOf(record: Pick<Card, "due" | "status">, now: Date): DueState | null {
	const day = record.due?.match(/^(\d{4})-(\d{2})-(\d{2})/);
	if (!day) return null;
	const due = new Date(Number(day[1]), Number(day[2]) - 1, Number(day[3]));
	const days = localDay(due) - localDay(now);
	const finished = phaseOf(record.status) === "done" || record.status === "Deprioritised";
	const date = due.toLocaleDateString(undefined, { day: "numeric", month: "short" });
	const title = `Due ${due.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long", year: "numeric" })}`;
	const held = null;
	if (finished) return { tone: "later", label: date, title, held };
	if (days < 0) return { tone: "overdue", label: days === -1 ? "Overdue 1 day" : `Overdue ${-days} days`, title, held };
	if (days === 0) return { tone: "soon", label: "Due today", title, held };
	if (days === 1) return { tone: "soon", label: "Due tomorrow", title, held };
	if (days <= 3)
		return { tone: "soon", label: `Due ${due.toLocaleDateString(undefined, { weekday: "short" })}`, title, held };
	return { tone: "later", label: `Due ${date}`, title, held };
}

export const SPLIT_ABOVE = 5;

export function bounces(record: Pick<Card, "back_from">) {
	return Object.entries(record.back_from ?? {}).filter(([, count]) => count > 0);
}

const OVERRUN_PHASES = ["dev", "review", "validate"];

export function showsOverrun(record: Pick<Card, "overrunning" | "status">) {
	return Boolean(record.overrunning) && OVERRUN_PHASES.includes(phaseOf(record.status));
}

export function overrunTitle(record: Pick<Card, "type" | "timebox_mins" | "complexity">) {
	return record.type === "Timebox" && record.timebox_mins
		? `Its dev time has run past its ${record.timebox_mins}-minute timebox`
		: `Its dev time has run past ${record.complexity ?? 0} points of working time`;
}

export function manualRank(record: Pick<Card, "id" | "rank">) {
	return record.rank ?? -Number(record.id.split("-").at(-1));
}

export function ago(stamp: string, now = Date.now()) {
	const date = new Date(stamp);
	if (Number.isNaN(date.getTime())) return stamp;
	const minutes = Math.round((now - date.getTime()) / 60000);
	if (minutes < 1) return "just now";
	if (minutes < 60) return `${minutes}m ago`;
	const hours = Math.round(minutes / 60);
	if (hours < 24) return `${hours}h ago`;
	const days = Math.round(hours / 24);
	if (days < 7) return `${days}d ago`;
	return date.toLocaleDateString(undefined, { day: "numeric", month: "short" });
}

const DAY = 86400000;

export function doneWithin(record: Pick<Card, "dates" | "moved">, days: number, now = Date.now()) {
	const stamps = [record.dates?.Done, record.moved].map((stamp) => new Date(stamp ?? "").getTime());
	const at = Math.max(...stamps.filter((stamp) => !Number.isNaN(stamp)));
	return Number.isFinite(at) && now - at <= days * DAY;
}

export function movedTo(status: string): Pick<Card, "status" | "moved"> {
	return { status, moved: new Date().toISOString() };
}
