import { type Kind, manualRank, showsOverrun, type Card as Stub, TYPES } from "@/lib/shared";

export type GroupBy = "" | "epic" | "project" | "type" | "sprint" | "label";

export const GROUPINGS: Record<Kind, [GroupBy, string][]> = {
	card: [
		["", "No grouping"],
		["epic", "By epic"],
		["project", "By project"],
		["type", "By type"],
		["sprint", "By sprint"],
		["label", "By label"],
	],
	epic: [
		["", "No grouping"],
		["project", "By project"],
		["label", "By label"],
	],
};

export function groupingOf(kind: Kind, groupBy: string | undefined): GroupBy {
	return GROUPINGS[kind].find(([key]) => key === groupBy)?.[0] ?? "";
}

export type Sort = "manual" | "newest" | "oldest" | "complexity" | "moved" | "days";
export type Layout = "board" | "list" | "table";

export const LAYOUTS: [Layout, string][] = [
	["board", "Board"],
	["list", "List"],
	["table", "Table"],
];

export type View = {
	query: string;
	types: string[];
	epic: string;
	labels: string[];
	urgent: boolean;
	blocked: boolean;
	claimed: boolean;
	overrunning: boolean;
	hideEmpty: boolean;
	sort: Sort;
	groupBy: GroupBy;
	tableSort: string;
	layout: Layout;
	collapsed: string[];
	listCollapsed: string[];
};

export const DEFAULT_VIEW: View = {
	query: "",
	types: [],
	epic: "",
	labels: [],
	urgent: false,
	blocked: false,
	claimed: false,
	overrunning: false,
	hideEmpty: false,
	sort: "manual",
	groupBy: "",
	tableSort: "",
	layout: "board",
	collapsed: ["Done", "Deprioritised"],
	listCollapsed: ["Done", "Deprioritised"],
};

export const COLLAPSED: Record<Kind, string[]> = { card: ["Done", "Deprioritised"], epic: ["Epic Done"] };

export function defaultView(kind: Kind): View {
	return { ...DEFAULT_VIEW, collapsed: COLLAPSED[kind], listCollapsed: COLLAPSED[kind] };
}

export function restoredView(kind: Kind, saved: Partial<View>): View {
	const known: Partial<View> = Object.fromEntries(Object.entries(saved).filter(([key]) => key in DEFAULT_VIEW));
	const collapsed = known.collapsed ?? COLLAPSED[kind];
	return { ...defaultView(kind), ...known, collapsed, listCollapsed: known.listCollapsed ?? collapsed };
}

export function collapsedIn(view: View): string[] {
	return view.layout === "list" ? view.listCollapsed : view.collapsed;
}

export function toggledIn(view: View, column: string): Partial<View> {
	const now = collapsedIn(view);
	const next = now.includes(column) ? now.filter((other) => other !== column) : [...now, column];
	return view.layout === "list" ? { listCollapsed: next } : { collapsed: next };
}
export const TOGGLES = [
	["urgent", "Urgent"],
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
		return saved ? restoredView(kind, JSON.parse(saved)) : null;
	} catch {
		return null;
	}
}

export function saveView(kind: Kind, view: View) {
	try {
		window.localStorage.setItem(storageKey(kind), JSON.stringify(view));
	} catch {}
}

function lastParentKey(kind: Kind) {
	return kind === "card" ? "cockpit-new-card-epic" : "cockpit-new-epic-project";
}

export function loadLastParent(kind: Kind): string | null {
	try {
		window.localStorage.removeItem("cockpit-quick-add-epic");
		window.localStorage.removeItem("cockpit-quick-add-project");
		return window.localStorage.getItem(lastParentKey(kind));
	} catch {
		return null;
	}
}

export function saveLastParent(kind: Kind, id: string) {
	try {
		window.localStorage.setItem(lastParentKey(kind), id);
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
	if (view.labels.length > 0 && !(stub.labels ?? []).some((label) => view.labels.includes(label))) return false;
	if (view.urgent && !stub.urgent) return false;
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

export const URGENT_LANE = "urgent";

export type Swimlane = { key: string; label: string; value: string | null; urgent: boolean; stubs: Stub[] };

export type GroupContext = {
	names: Record<string, Record<string, string>>;
	order: Record<string, string[]>;
	epicProjects: Record<string, string | null | undefined>;
};

export function groupValue(stub: Stub, groupBy: GroupBy, context: GroupContext): string | null {
	switch (groupBy) {
		case "epic":
			return stub.epic || null;
		case "project":
			return stub.project || (stub.epic ? context.epicProjects[stub.epic] : null) || null;
		case "type":
			return stub.type || null;
		case "sprint":
			return stub.sprint || null;
		case "label":
			return stub.labels?.[0] ?? null;
		default:
			return null;
	}
}

function laneOrder(groupBy: GroupBy, context: GroupContext): string[] {
	return groupBy === "type" ? [...TYPES] : (context.order[groupBy] ?? []);
}

export function swimlanesOf(stubs: Stub[], kind: Kind, groupBy: GroupBy, context: GroupContext): Swimlane[] | null {
	const urgent = kind === "card" ? stubs.filter((stub) => stub.urgent) : [];
	const rest = kind === "card" ? stubs.filter((stub) => !stub.urgent) : stubs;
	if (!groupBy && urgent.length === 0) return null;
	const lanes: Swimlane[] = [];
	if (urgent.length > 0) lanes.push({ key: URGENT_LANE, label: "Urgent", value: "true", urgent: true, stubs: urgent });
	if (!groupBy) {
		lanes.push({ key: "rest", label: "Everything else", value: null, urgent: false, stubs: rest });
		return lanes;
	}
	const groups = new Map<string | null, Stub[]>();
	for (const stub of rest) {
		const value = groupValue(stub, groupBy, context);
		groups.set(value, [...(groups.get(value) ?? []), stub]);
	}
	const known = laneOrder(groupBy, context);
	const rank = (value: string) => {
		const index = known.indexOf(value);
		return index < 0 ? known.length : index;
	};
	const values = [...groups.keys()]
		.filter((value): value is string => value !== null)
		.sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
	const names = context.names[groupBy] ?? {};
	for (const value of values) {
		lanes.push({ key: `${groupBy}:${value}`, label: names[value] ?? value, value, urgent: false, stubs: groups.get(value) ?? [] });
	}
	const none = groups.get(null);
	if (none) lanes.push({ key: `${groupBy}:`, label: `No ${groupBy}`, value: null, urgent: false, stubs: none });
	return lanes;
}

export type FieldChange = { field: string; value: string; change: Partial<Stub> };

export function droppedInto(
	stub: Stub,
	from: Swimlane | undefined,
	to: Swimlane,
	groupBy: GroupBy,
	kind: Kind,
	context?: GroupContext,
): FieldChange[] | string {
	if (from?.key === to.key) return [];
	if (to.urgent) return [{ field: "urgent", value: "true", change: { urgent: true } }];
	const changes: FieldChange[] = from?.urgent ? [{ field: "urgent", value: "", change: { urgent: false } }] : [];
	const value = to.value;
	switch (groupBy) {
		case "epic":
			if (value && value !== stub.epic) changes.push({ field: "epic", value, change: { epic: value } });
			else if (!value) return `Every card has an epic, so ${stub.id} cannot be dropped where there is none.`;
			break;
		case "project":
			if (kind !== "epic") {
				if (context && value !== groupValue(stub, "project", context))
					return `A card's project is its epic's, so ${stub.id} moves to another project's lane only when its epic does.`;
				break;
			}
			if (value && value !== stub.project) changes.push({ field: "project", value, change: { project: value } });
			else if (!value) return `Every epic has a project, so ${stub.id} cannot be dropped where there is none.`;
			break;
		case "type":
			if (value && value !== stub.type) changes.push({ field: "type", value, change: { type: value as Stub["type"] } });
			break;
		case "sprint":
			if ((value ?? "") !== (stub.sprint ?? "")) changes.push({ field: "sprint", value: value ?? "", change: { sprint: value } });
			break;
		case "label": {
			const kept = (stub.labels ?? []).filter((label) => from?.urgent || label !== from?.value);
			const labels = value ? [value, ...kept.filter((label) => label !== value)] : from?.urgent ? kept : [];
			if (labels.join(",") !== (stub.labels ?? []).join(","))
				changes.push({ field: "labels", value: labels.join(", "), change: { labels } });
			break;
		}
	}
	return changes;
}
