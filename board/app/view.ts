import { type Card as Stub, type Kind, manualRank } from "@/lib/shared";

export type Sort = "manual" | "newest" | "oldest" | "complexity" | "moved";
export type Layout = "board" | "list";

export type View = {
	query: string;
	types: string[];
	epic: string;
	blocked: boolean;
	claimed: boolean;
	hideEmpty: boolean;
	sort: Sort;
	layout: Layout;
	collapsed: string[];
};

export const DEFAULT_VIEW: View = {
	query: "",
	types: [],
	epic: "",
	blocked: false,
	claimed: false,
	hideEmpty: false,
	sort: "manual",
	layout: "board",
	collapsed: ["Done", "Deprioritised"],
};

export const COLLAPSED: Record<Kind, string[]> = { card: ["Done", "Deprioritised"], epic: ["Epic Done"] };
export const TOGGLES = [
	["blocked", "Blocked"],
	["claimed", "Claimed"],
] as const;

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

function lastMoved(stub: Stub) {
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
		case "moved":
			return (a: Stub, b: Stub) => lastMoved(b).localeCompare(lastMoved(a));
		case "manual":
			return (a: Stub, b: Stub) => manualRank(a) - manualRank(b);
		default:
			return (a: Stub, b: Stub) => ticketNumber(b) - ticketNumber(a);
	}
}

export function matches(stub: Stub, view: View) {
	const query = view.query.trim().toLowerCase();
	if (query && !`${stub.id} ${stub.name} ${stub.epic ?? ""}`.toLowerCase().includes(query)) return false;
	if (view.types.length > 0 && !view.types.includes(stub.type ?? "")) return false;
	if (view.epic && (stub.epic ?? "") !== view.epic) return false;
	if (view.blocked && !stub.blocked) return false;
	if (view.claimed && !stub.session) return false;
	return true;
}

export type Near = { id: string; name: string } | null;

export type Neighbours = { previous: Near; next: Near; position: number; total: number } | null;

export function neighboursIn(column: Stub[], id: string, view: View | null): Neighbours {
	const sorted = [...column].sort(sorter(view?.sort ?? "manual"));
	const filtered = view ? sorted.filter((stub) => matches(stub, view)) : sorted;
	const lane = filtered.some((stub) => stub.id === id) ? filtered : sorted;
	const index = lane.findIndex((stub) => stub.id === id);
	if (index < 0) return null;
	const near = (stub?: Stub) => (stub ? { id: stub.id, name: stub.name } : null);
	return { previous: near(lane[index - 1]), next: near(lane[index + 1]), position: index + 1, total: lane.length };
}
