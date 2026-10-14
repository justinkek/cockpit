import { inPreset, type Kind, manualRank, showsOverrun, type Card as Stub } from "@/lib/shared";

export type Sort = "manual" | "newest" | "oldest" | "complexity" | "moved" | "days";
export type Layout = "board" | "list" | "table";

export const LAYOUTS: [Layout, string][] = [
	["board", "Board"],
	["list", "List"],
	["table", "Table"],
];

export type View = {
	preset: string;
	query: string;
	types: string[];
	epic: string;
	blocked: boolean;
	claimed: boolean;
	overrunning: boolean;
	hideEmpty: boolean;
	sort: Sort;
	tableSort: string;
	layout: Layout;
	collapsed: string[];
};

export const DEFAULT_VIEW: View = {
	preset: "all",
	query: "",
	types: [],
	epic: "",
	blocked: false,
	claimed: false,
	overrunning: false,
	hideEmpty: false,
	sort: "manual",
	tableSort: "",
	layout: "board",
	collapsed: ["Done", "Deprioritised"],
};

export const COLLAPSED: Record<Kind, string[]> = { card: ["Done", "Deprioritised"], epic: ["Epic Done"] };
export const TOGGLES = [
	["blocked", "Blocked"],
	["claimed", "Claimed"],
	["overrunning", "Overrunning"],
] as const;

export const NO_EPIC = "none";

const EXCEPT = "!";

export function exceptEpic(id: string) {
	return `${EXCEPT}${id}`;
}

export function epicPasses(filter: string, epic?: string | null) {
	if (!filter) return true;
	if (filter === NO_EPIC) return !epic;
	if (filter.startsWith(EXCEPT)) return (epic ?? "") !== filter.slice(EXCEPT.length);
	return (epic ?? "") === filter;
}

export function onlyEpic(view: View) {
	return view.epic && view.epic !== NO_EPIC && !view.epic.startsWith(EXCEPT) ? view.epic : undefined;
}

export function storageKey(kind: Kind) {
	return kind === "card" ? "cockpit-board-view" : `cockpit-board-view-${kind}`;
}

export function loadView(kind: Kind): View | null {
	try {
		const saved = window.localStorage.getItem(storageKey(kind));
		return saved ? { ...DEFAULT_VIEW, collapsed: COLLAPSED[kind], ...JSON.parse(saved) } : null;
	} catch {
		return null;
	}
}

export function saveView(kind: Kind, view: View) {
	try {
		window.localStorage.setItem(storageKey(kind), JSON.stringify(view));
	} catch {}
}

function ticketNumber(stub: Stub) {
	return Number(stub.id.split("-").at(-1));
}

export function lastMoved(stub: Stub) {
	return (
		stub.moved ??
		Object.values(stub.dates ?? {})
			.sort()
			.at(-1) ??
		stub.created
	);
}

export function sorter(sort: Sort) {
	switch (sort) {
		case "oldest":
			return (a: Stub, b: Stub) => ticketNumber(a) - ticketNumber(b);
		case "complexity":
			return (a: Stub, b: Stub) => (b.complexity ?? -1) - (a.complexity ?? -1) || ticketNumber(b) - ticketNumber(a);
		case "days":
			return (a: Stub, b: Stub) =>
				(b.days_in_column ?? 0) - (a.days_in_column ?? 0) || lastMoved(a).localeCompare(lastMoved(b));
		case "moved":
			return (a: Stub, b: Stub) => lastMoved(b).localeCompare(lastMoved(a));
		case "manual":
			return (a: Stub, b: Stub) => manualRank(a) - manualRank(b);
		default:
			return (a: Stub, b: Stub) => ticketNumber(b) - ticketNumber(a);
	}
}

export type Found = { names?: Record<string, string>; inContent?: Set<string> };

export function matches(stub: Stub, view: View, found: Found = {}) {
	const query = view.query.trim().toLowerCase();
	const epic = stub.epic ? `${stub.epic} ${found.names?.[stub.epic] ?? ""}` : "";
	if (query && !`${stub.id} ${stub.name} ${epic}`.toLowerCase().includes(query) && !found.inContent?.has(stub.id))
		return false;
	if (view.types.length > 0 && !view.types.includes(stub.type ?? "")) return false;
	if (!epicPasses(view.epic, stub.epic)) return false;
	if (!inPreset(stub, view.preset)) return false;
	if (view.blocked && !stub.blocked) return false;
	if (view.claimed && !stub.session) return false;
	if (view.overrunning && !showsOverrun(stub)) return false;
	return true;
}

export type Near = { id: string; name: string } | null;

export type Neighbours = { previous: Near; next: Near; position: number; total: number } | null;

export function neighboursIn(
	column: Stub[],
	id: string,
	view: View | null,
	found: Found = {},
	arrange: (sorted: Stub[]) => Stub[] = (sorted) => sorted,
): Neighbours {
	const sorted = arrange([...column].sort(sorter(view?.sort ?? "manual")));
	const filtered = view ? sorted.filter((stub) => matches(stub, view, found)) : sorted;
	const lane = filtered.some((stub) => stub.id === id) ? filtered : sorted;
	const index = lane.findIndex((stub) => stub.id === id);
	if (index < 0) return null;
	const near = (stub?: Stub) => (stub ? { id: stub.id, name: stub.name } : null);
	return { previous: near(lane[index - 1]), next: near(lane[index + 1]), position: index + 1, total: lane.length };
}
