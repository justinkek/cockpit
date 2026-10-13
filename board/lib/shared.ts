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

export function walkColumns(kind: Kind) {
	return kind === "epic" ? EPIC_COLUMNS : CARD_COLUMNS;
}

export function boardColumns(kind: Kind) {
	return kind === "epic" ? EPIC_COLUMNS : CARD_BOARD_COLUMNS;
}

export const FIBONACCI = [0, 1, 2, 3, 5, 8, 13, 21, 34];

export type Card = {
	id: string;
	name: string;
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
	session?: string | null;
	claimed_at?: string | null;
	prs?: string | null;
	cost_usd?: number | null;
	tokens_k?: number | null;
	created: string;
	rank?: number | null;
	models?: Record<string, string>;
	back_from?: Record<string, number>;
	dates?: Record<string, string>;
	notion_url?: string | null;
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
