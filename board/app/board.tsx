"use client";

import {
	type CollisionDetection,
	DndContext,
	type DragEndEvent,
	DragOverlay,
	type DragStartEvent,
	KeyboardSensor,
	PointerSensor,
	pointerWithin,
	rectIntersection,
	TouchSensor,
	useDraggable,
	useDroppable,
	useSensor,
	useSensors,
} from "@dnd-kit/core";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createContext, useContext, useEffect, useId, useMemo, useRef, useState, useTransition } from "react";
import { createCard, dropCard, editCard, linkCards, undoChange } from "@/app/actions";
import { Content } from "@/app/content";
import { Fields, type Handlers, Links, type Lists, linkChange, Title } from "@/app/fields";
import { type Undoable, UndoToast, undoable } from "@/app/toast";
import {
	boardColumns,
	dueState,
	fieldName,
	type Kind,
	kindOf,
	type Named,
	phaseOf,
	type Card as Stub,
	TYPES,
} from "@/lib/shared";

const Names = createContext<Record<string, string>>({});

type Notice = { id: string; text: string } | null;

function NoticeBar({ notice, onDismiss }: { notice: Notice; onDismiss: () => void }) {
	if (!notice) return null;
	return (
		<p className="notice error" role="alert">
			<span>{notice.text}</span>
			<button type="button" className="quiet" onClick={onDismiss}>
				Dismiss
			</button>
		</p>
	);
}

type Sort = "manual" | "newest" | "oldest" | "complexity" | "moved";
type Layout = "board" | "list";

type View = {
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

const DEFAULT_VIEW: View = {
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

const COLLAPSED: Record<Kind, string[]> = { card: ["Done", "Deprioritised"], epic: ["Epic Done"] };
const TOGGLES = [
	["blocked", "Blocked"],
	["claimed", "Claimed"],
] as const;

function storageKey(kind: Kind) {
	return kind === "card" ? "cockpit-board-view" : `cockpit-board-view-${kind}`;
}

function loadView(kind: Kind): View | null {
	try {
		const saved = window.localStorage.getItem(storageKey(kind));
		return saved ? { ...DEFAULT_VIEW, collapsed: COLLAPSED[kind], ...JSON.parse(saved) } : null;
	} catch {
		return null;
	}
}

function saveView(kind: Kind, view: View) {
	try {
		window.localStorage.setItem(storageKey(kind), JSON.stringify(view));
	} catch {}
}

function ticketNumber(stub: Stub) {
	return Number(stub.id.split("-").at(-1));
}

function effectiveRank(stub: Stub) {
	return stub.rank ?? -ticketNumber(stub);
}

const FROM_PANEL = "peek:";

function draggedId(active: string | number) {
	return String(active).replace(FROM_PANEL, "");
}

function PanelHandle({ id }: { id: string }) {
	const [covering, setCovering] = useState(false);
	useEffect(() => {
		const query = window.matchMedia("(width < 760px)");
		const update = () => setCovering(query.matches);
		update();
		query.addEventListener("change", update);
		return () => query.removeEventListener("change", update);
	}, []);
	const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
		id: `${FROM_PANEL}${id}`,
		disabled: covering,
	});
	return (
		<button
			ref={setNodeRef}
			type="button"
			className={`ident drag-handle${isDragging ? " dragging" : ""}`}
			title="Drag to a column"
			{...listeners}
			{...attributes}
			aria-roledescription="Drag to a column"
		>
			<span aria-hidden="true">⠿</span>
			{id}
		</button>
	);
}

const collisions: CollisionDetection = (args) => {
	const within = pointerWithin(args);
	const card = within.find((hit) => String(hit.id).startsWith("card:"));
	if (card) return [card];
	return within.length > 0 ? within : rectIntersection(args);
};

function lastMoved(stub: Stub) {
	return (
		stub.moved ??
		Object.values(stub.dates ?? {})
			.sort()
			.at(-1) ??
		stub.created
	);
}

function sorter(sort: Sort) {
	switch (sort) {
		case "oldest":
			return (a: Stub, b: Stub) => ticketNumber(a) - ticketNumber(b);
		case "complexity":
			return (a: Stub, b: Stub) => (b.complexity ?? -1) - (a.complexity ?? -1) || ticketNumber(b) - ticketNumber(a);
		case "moved":
			return (a: Stub, b: Stub) => lastMoved(b).localeCompare(lastMoved(a));
		case "manual":
			return (a: Stub, b: Stub) => effectiveRank(a) - effectiveRank(b);
		default:
			return (a: Stub, b: Stub) => ticketNumber(b) - ticketNumber(a);
	}
}

function matches(stub: Stub, view: View) {
	const query = view.query.trim().toLowerCase();
	if (query && !`${stub.id} ${stub.name} ${stub.epic ?? ""}`.toLowerCase().includes(query)) return false;
	if (view.types.length > 0 && !view.types.includes(stub.type ?? "")) return false;
	if (view.epic && (stub.epic ?? "") !== view.epic) return false;
	if (view.blocked && !stub.blocked) return false;
	if (view.claimed && !stub.session) return false;
	return true;
}

function filterCount(view: View) {
	return [
		view.query.trim() !== "",
		view.types.length > 0,
		view.epic !== "",
		view.blocked,
		view.claimed,
	].filter(Boolean).length;
}

function StatusDot({ status }: { status: string }) {
	return <span className={`dot phase-${phaseOf(status)}`} aria-hidden="true" />;
}

function TypeMark({ type }: { type: string }) {
	return <span className={`type type-${type.toLowerCase()}`}>{type}</span>;
}

function EpicPill({ epic }: { epic?: string | null }) {
	const names = useContext(Names);
	if (!epic) return null;
	return <span className="pill epic">{names[epic] ?? epic}</span>;
}

function DueChip({ stub }: { stub: Stub }) {
	const due = dueState(stub);
	if (!due) return null;
	return (
		<span className={`pill due due-${due.tone}`} title={due.title} suppressHydrationWarning>
			{due.label}
		</span>
	);
}

function CardBody({ stub }: { stub: Stub }) {
	return (
		<>
			<span className="card-top">
				<span className="ident">{stub.id}</span>
				{stub.session && <span className="claimed" title={`Claimed by ${stub.session}`} />}
			</span>
			<span className="name">{stub.name}</span>
			<span className="meta">
				{stub.type && <TypeMark type={stub.type} />}
				{stub.complexity != null && <span className="pill">{stub.complexity}</span>}
				{stub.blocked && <span className="pill blocked">Blocked</span>}
				<DueChip stub={stub} />
				<EpicPill epic={stub.epic} />
			</span>
		</>
	);
}

function Points({ stubs }: { stubs: Stub[] }) {
	const sized = stubs.filter((stub) => stub.complexity != null);
	if (sized.length === 0) return null;
	const total = sized.reduce((sum, stub) => sum + (stub.complexity ?? 0), 0);
	return (
		<span className="lane-points" title={`${total} points across ${sized.length} sized of ${stubs.length}`}>
			{total} pts
		</span>
	);
}

function Card({ stub, pending, onOpen }: { stub: Stub; pending: boolean; onOpen: (id: string) => void }) {
	const { attributes, listeners, setNodeRef, isDragging } = useDraggable({ id: stub.id });
	const drop = useDroppable({ id: `card:${stub.id}` });
	return (
		<li
			ref={(node) => {
				setNodeRef(node);
				drop.setNodeRef(node);
			}}
			className={
				[isDragging && "dragging", drop.isOver && !isDragging && "insert"].filter(Boolean).join(" ") || undefined
			}
		>
			<button
				type="button"
				{...listeners}
				{...attributes}
				className={`card${pending ? " pending" : ""}`}
				onClick={() => onOpen(stub.id)}
			>
				<CardBody stub={stub} />
			</button>
		</li>
	);
}

function QuickAdd({
	column,
	open,
	onOpenChange,
	onCreate,
}: {
	column: string;
	open: boolean;
	onOpenChange: (open: boolean) => void;
	onCreate: (name: string) => Promise<boolean>;
}) {
	const [name, setName] = useState("");
	const [busy, setBusy] = useState(false);
	const box = useRef<HTMLInputElement>(null);
	useEffect(() => {
		if (open) box.current?.focus();
	}, [open]);
	if (!open) {
		return (
			<button type="button" className="quick-add-open" onClick={() => onOpenChange(true)}>
				+ New in {column}
			</button>
		);
	}
	return (
		<form
			className="quick-add"
			onSubmit={async (event) => {
				event.preventDefault();
				if (!name.trim() || busy) return;
				setBusy(true);
				const made = await onCreate(name.trim());
				setBusy(false);
				if (made) setName("");
				box.current?.focus();
			}}
		>
			<input
				ref={box}
				value={name}
				aria-label={`New card name in ${column}`}
				placeholder="Name, then Enter"
				disabled={busy}
				onChange={(event) => setName(event.target.value)}
				onKeyDown={(event) => {
					if (event.key === "Escape") {
						event.stopPropagation();
						setName("");
						onOpenChange(false);
					}
				}}
				onBlur={() => {
					if (!name.trim() && !busy) onOpenChange(false);
				}}
			/>
		</form>
	);
}

type Adding = { open: boolean; onOpenChange: (open: boolean) => void; onCreate: (name: string) => Promise<boolean> };

function Lane({
	column,
	stubs,
	collapsed,
	onToggle,
	pending,
	onOpen,
	adding,
}: {
	column: string;
	stubs: Stub[];
	collapsed: boolean;
	onToggle: () => void;
	pending: Set<string>;
	onOpen: (id: string) => void;
	adding: Adding;
}) {
	const { setNodeRef, isOver } = useDroppable({ id: column });
	return (
		<section ref={setNodeRef} className={`lane${collapsed ? " collapsed" : ""}${isOver ? " over" : ""}`}>
			<button type="button" className="lane-head" onClick={onToggle} aria-expanded={!collapsed}>
				<StatusDot status={column} />
				<span className="lane-name">{column}</span>
				<span className="count">{stubs.length}</span>
				<Points stubs={stubs} />
			</button>
			{!collapsed && (
				<ul>
					{stubs.map((stub) => (
						<Card key={stub.id} stub={stub} pending={pending.has(stub.id)} onOpen={onOpen} />
					))}
				</ul>
			)}
			{!collapsed && <QuickAdd column={column} {...adding} />}
		</section>
	);
}

function ListRow({ stub, pending, onOpen }: { stub: Stub; pending: boolean; onOpen: (id: string) => void }) {
	const { attributes, listeners, setNodeRef, isDragging } = useDraggable({ id: stub.id });
	const drop = useDroppable({ id: `card:${stub.id}` });
	return (
		<li
			ref={(node) => {
				setNodeRef(node);
				drop.setNodeRef(node);
			}}
			className={
				[isDragging && "dragging", drop.isOver && !isDragging && "insert"].filter(Boolean).join(" ") || undefined
			}
		>
			<button
				type="button"
				{...listeners}
				{...attributes}
				className={`row${pending ? " pending" : ""}`}
				onClick={() => onOpen(stub.id)}
			>
				<span className="ident">{stub.id}</span>
				<StatusDot status={stub.status} />
				<span className="name">{stub.name}</span>
				<span className="row-meta">
					{stub.blocked && <span className="pill blocked">Blocked</span>}
					<DueChip stub={stub} />
					<EpicPill epic={stub.epic} />
					{stub.type && <TypeMark type={stub.type} />}
					<span className="points">{stub.complexity ?? ""}</span>
				</span>
			</button>
		</li>
	);
}

function ListGroup({
	column,
	stubs,
	collapsed,
	onToggle,
	pending,
	onOpen,
	adding,
}: {
	column: string;
	stubs: Stub[];
	collapsed: boolean;
	onToggle: () => void;
	pending: Set<string>;
	onOpen: (id: string) => void;
	adding: Adding;
}) {
	const { setNodeRef, isOver } = useDroppable({ id: column });
	return (
		<section ref={setNodeRef} className={`group${isOver ? " over" : ""}`}>
			<button type="button" className="group-head" onClick={onToggle} aria-expanded={!collapsed}>
				<span className="caret">{collapsed ? "▸" : "▾"}</span>
				<StatusDot status={column} />
				<span className="lane-name">{column}</span>
				<span className="count">{stubs.length}</span>
				<Points stubs={stubs} />
			</button>
			{!collapsed && (
				<ul>
					{stubs.map((stub) => (
						<ListRow key={stub.id} stub={stub} pending={pending.has(stub.id)} onOpen={onOpen} />
					))}
				</ul>
			)}
			{!collapsed && <QuickAdd column={column} {...adding} />}
		</section>
	);
}

function Peek({
	stub,
	kind,
	cards,
	lists,
	handlers,
	notice,
	onDismiss,
	onClose,
}: {
	stub: Stub;
	kind: Kind;
	cards: (Named & { status: string })[];
	lists: Lists;
	handlers: Handlers;
	notice: Notice;
	onDismiss: () => void;
	onClose: () => void;
}) {
	const dates = Object.entries(stub.dates ?? {}).sort(([, a], [, b]) => a.localeCompare(b));
	const panel = useRef<HTMLElement>(null);
	const number = stub.id.split("-").at(-1);
	useEffect(() => {
		panel.current?.scrollTo({ top: 0 });
	}, [number]);
	return (
		<aside className="peek" ref={panel} aria-label={`${stub.id} details`}>
			<header className="peek-head">
				<PanelHandle id={stub.id} />
				<span className="peek-actions">
					<Link href={`/card/${stub.id}`} className="quiet-link">
						Open
					</Link>
					<button type="button" className="quiet" onClick={onClose} title="Close (Esc)" aria-keyshortcuts="Escape">
						Close
					</button>
				</span>
			</header>
			<NoticeBar notice={notice} onDismiss={onDismiss} />
			<Title
				id={stub.id}
				className="peek-title"
				value={stub.name}
				onCommit={(name) => handlers.onEdit("name", name, { name })}
			/>
			<Fields record={stub} lists={lists} handlers={handlers} />
			<Links record={stub} lists={lists} handlers={handlers} />
			<dl className="props">
				<dt>Claimed by</dt>
				<dd>{stub.session ?? <span className="empty">Nobody</span>}</dd>
				{stub.cost_usd != null && (
					<>
						<dt>Cost</dt>
						<dd>
							${stub.cost_usd}
							{stub.tokens_k != null && ` · ${stub.tokens_k}k tokens`}
						</dd>
					</>
				)}
			</dl>
			{kind === "epic" && (
				<section className="timeline">
					<h3>
						Cards <span className="count">{cards.length}</span>
					</h3>
					<ol>
						{cards.map((card) => (
							<li key={card.id}>
								<StatusDot status={card.status} />
								<Link href={`/?open=${card.id}`}>{card.name}</Link>
								<span className="ident">{card.id}</span>
							</li>
						))}
					</ol>
				</section>
			)}
			{dates.length > 0 && (
				<section className="timeline">
					<h3>Activity</h3>
					<ol>
						{dates.map(([column, stamp]) => (
							<li key={column}>
								<StatusDot status={column} />
								<span>{column}</span>
								<time dateTime={stamp}>{new Date(stamp).toLocaleString()}</time>
							</li>
						))}
					</ol>
				</section>
			)}
			<Content id={stub.id} />
		</aside>
	);
}

export function Board({
	initial,
	kind = "card",
	lists,
	children = {},
}: {
	initial: Stub[];
	kind?: Kind;
	lists: Lists;
	children?: Record<string, (Named & { status: string })[]>;
}) {
	const epics = lists.epics;
	const router = useRouter();
	const [stubs, setStubs] = useState(initial);
	const [view, setView] = useState<View>({ ...DEFAULT_VIEW, collapsed: COLLAPSED[kind] });
	const [loaded, setLoaded] = useState(false);
	const [dragging, setDragging] = useState<Stub | null>(null);
	const [pending, setPending] = useState<Set<string>>(new Set());
	const [notice, setNotice] = useState<Notice>(null);
	const [openId, setOpenId] = useState<string | null>(null);
	const [filtersOpen, setFiltersOpen] = useState(false);
	const [toast, setToast] = useState<Undoable | null>(null);
	const [undoing, setUndoing] = useState(false);
	const [addingIn, setAddingIn] = useState<string | null>(null);
	const [, startTransition] = useTransition();
	const search = useRef<HTMLInputElement>(null);
	const dndId = useId();

	useEffect(() => setStubs(initial), [initial]);

	useEffect(() => {
		const saved = loadView(kind);
		const params = new URLSearchParams(window.location.search);
		const epic = params.get("epic");
		if (saved || epic) setView({ ...(saved ?? DEFAULT_VIEW), ...(epic ? { epic } : {}) });
		const opening = params.get("open")?.toUpperCase();
		if (opening) {
			const number = opening.split("-").at(-1);
			const found =
				initial.find((stub) => stub.id === opening) ??
				initial.find((stub) => kindOf(stub.id) === kindOf(opening) && stub.id.split("-").at(-1) === number);
			setOpenId(found?.id ?? opening);
		}
		setLoaded(true);
	}, []);

	useEffect(() => {
		if (loaded) saveView(kind, view);
	}, [view, loaded]);

	useEffect(() => {
		if (!loaded) return;
		const url = new URL(window.location.href);
		if (openId) url.searchParams.set("open", openId);
		else url.searchParams.delete("open");
		if (url.href !== window.location.href) window.history.replaceState(null, "", url);
	}, [openId, loaded]);

	useEffect(() => {
		function onKey(event: KeyboardEvent) {
			const typing = event.target instanceof HTMLElement && /^(INPUT|SELECT|TEXTAREA)$/.test(event.target.tagName);
			if (event.key === "Escape") {
				if (typing) (event.target as HTMLElement).blur();
				else setOpenId(null);
			} else if (event.key === "/" && !typing) {
				event.preventDefault();
				search.current?.focus();
			}
		}
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	}, []);

	const sensors = useSensors(
		useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
		useSensor(TouchSensor, { activationConstraint: { delay: 220, tolerance: 6 } }),
		useSensor(KeyboardSensor),
	);

	const names = useMemo(() => Object.fromEntries(epics.map((epic) => [epic.id, epic.name])), [epics]);
	const columnsOfKind = boardColumns(kind);
	const visible = useMemo(() => stubs.filter((stub) => matches(stub, view)).sort(sorter(view.sort)), [stubs, view]);
	const columns = useMemo(() => {
		const extra = [...new Set(stubs.map((stub) => stub.status))].filter((status) => !columnsOfKind.includes(status));
		const all = [...columnsOfKind, ...extra];
		return view.hideEmpty ? all.filter((column) => visible.some((stub) => stub.status === column)) : all;
	}, [stubs, visible, view.hideEmpty, columnsOfKind]);
	const open = openId ? (stubs.find((stub) => stub.id === openId) ?? null) : null;

	function update(change: Partial<View>) {
		setView((current) => ({ ...current, ...change }));
	}

	function toggleType(type: string) {
		update({ types: view.types.includes(type) ? view.types.filter((t) => t !== type) : [...view.types, type] });
	}

	function toggleColumn(column: string) {
		update({
			collapsed: view.collapsed.includes(column)
				? view.collapsed.filter((c) => c !== column)
				: [...view.collapsed, column],
		});
	}

	function markPending(id: string, on: boolean) {
		setPending((current) => {
			const next = new Set(current);
			if (on) next.add(id);
			else next.delete(id);
			return next;
		});
	}

	function apply(
		id: string,
		optimistic: Partial<Stub>,
		request: () => Promise<{ record?: Stub; error?: string; moved?: string; undo?: string }>,
		label: string,
	) {
		const before = stubs.find((s) => s.id === id);
		if (!before) return;
		setNotice(null);
		setStubs((current) => current.map((s) => (s.id === id ? { ...s, ...optimistic } : s)));
		markPending(id, true);
		startTransition(async () => {
			const result = await request();
			markPending(id, false);
			if (result.error) {
				const moved = result.moved;
				setStubs((current) => current.map((s) => (s.id === id ? before : s)));
				setNotice({ id: moved ?? id, text: moved ? result.error : `${id}: ${result.error}` });
				if (moved) {
					setOpenId((opened) => (opened === id ? moved : opened));
					router.refresh();
				}
				return;
			}
			const fresh = result.record;
			if (fresh) {
				setStubs((current) => current.map((s) => (s.id === id ? fresh : s)));
				if (fresh.id !== id) setOpenId((opened) => (opened === id ? fresh.id : opened));
				setToast(undoable(fresh.id, result.undo, label.replace(id, fresh.id)));
			}
			router.refresh();
		});
	}

	function undo(shown: Undoable) {
		setUndoing(true);
		setNotice(null);
		startTransition(async () => {
			const result = await undoChange(shown.id, shown.since);
			setUndoing(false);
			setToast(null);
			if (result.error) {
				setNotice({ id: result.moved ?? shown.id, text: `Could not undo: ${result.error}` });
				router.refresh();
				return;
			}
			const fresh = result.record;
			if (fresh) {
				setStubs((current) => current.map((s) => (s.id === shown.id ? fresh : s)));
				if (fresh.id !== shown.id) setOpenId((opened) => (opened === shown.id ? fresh.id : opened));
			}
			router.refresh();
		});
	}

	function move(id: string, column: string, rank?: number) {
		const stub = stubs.find((s) => s.id === id);
		if (!stub || (stub.status === column && rank === undefined)) return;
		const label = stub.status === column ? `Reordered ${id} in ${column}` : `Moved ${id} to ${column}`;
		apply(id, rank === undefined ? { status: column } : { status: column, rank }, () => dropCard(id, column, rank), label);
	}

	function placement(id: string, overId: string): { column: string; rank?: number } | null {
		if (!overId.startsWith("card:")) {
			if (view.sort !== "manual") return { column: overId };
			const lane = visible.filter((stub) => stub.status === overId && stub.id !== id);
			const last = lane.at(-1);
			return { column: overId, rank: last ? effectiveRank(last) + 1 : undefined };
		}
		const target = stubs.find((stub) => stub.id === overId.slice(5));
		if (!target || target.id === id) return null;
		if (view.sort !== "manual") return { column: target.status };
		const lane = visible.filter((stub) => stub.status === target.status && stub.id !== id);
		const index = lane.findIndex((stub) => stub.id === target.id);
		const before = index > 0 ? effectiveRank(lane[index - 1]) : effectiveRank(target) - 1;
		return { column: target.status, rank: (before + effectiveRank(target)) / 2 };
	}

	function handlersFor(stub: Stub): Handlers {
		return {
			onMove: (column) => move(stub.id, column),
			onEdit: (field, value, change) =>
				apply(stub.id, change, () => editCard(stub.id, field, value), `Changed the ${fieldName(field)} of ${stub.id}`),
			onLink: (parent, child, linked) =>
				apply(
					stub.id,
					linkChange(stub, parent, child, linked),
					() => linkCards(stub.id, parent, child, linked),
					linked ? `Linked ${parent} to ${child}` : `Unlinked ${parent} from ${child}`,
				),
			onOpen: setOpenId,
		};
	}

	async function create(column: string, name: string): Promise<boolean> {
		setNotice(null);
		const lane = visible.filter((stub) => stub.status === column);
		const last = lane.at(-1);
		const result = await createCard(kind, name, column, {
			type: view.types.length === 1 ? view.types[0] : undefined,
			epic: view.epic || undefined,
			rank: view.sort === "manual" && last ? effectiveRank(last) + 1 : undefined,
		});
		const fresh = result.record;
		if (!fresh) {
			setNotice({ id: column, text: `Could not create the card: ${result.error ?? "board-card made nothing"}` });
			return false;
		}
		setStubs((current) => [...current, fresh]);
		router.refresh();
		return true;
	}

	function onDragStart(event: DragStartEvent) {
		const id = draggedId(event.active.id);
		setDragging(stubs.find((stub) => stub.id === id) ?? null);
	}

	function onDragEnd(event: DragEndEvent) {
		setDragging(null);
		if (!event.over) return;
		const id = draggedId(event.active.id);
		const place = placement(id, String(event.over.id));
		if (place) move(id, place.column, place.rank);
	}

	const count = filterCount(view);
	const groupProps = (column: string) => ({
		column,
		stubs: visible.filter((stub) => stub.status === column),
		collapsed: view.collapsed.includes(column),
		onToggle: () => toggleColumn(column),
		pending,
		onOpen: setOpenId,
		adding: {
			open: addingIn === column,
			onOpenChange: (open: boolean) => setAddingIn(open ? column : null),
			onCreate: (name: string) => create(column, name),
		},
	});

	return (
		<Names.Provider value={names}>
			<div className={`board${open ? " peeking" : ""}`}>
				<div className="toolbar">
					<div className="segmented" role="group" aria-label="Layout">
						{(["board", "list"] as const).map((layout) => (
							<button
								key={layout}
								type="button"
								className={view.layout === layout ? "on" : undefined}
								aria-pressed={view.layout === layout}
								onClick={() => update({ layout })}
							>
								{layout === "board" ? "Board" : "List"}
							</button>
						))}
					</div>
					<input
						ref={search}
						type="search"
						className="search"
						placeholder="Search  /"
						value={view.query}
						onChange={(event) => update({ query: event.target.value })}
					/>
					<button
						type="button"
						className={`chip-toggle filters-toggle${filtersOpen ? " on" : ""}`}
						aria-expanded={filtersOpen}
						onClick={() => setFiltersOpen(!filtersOpen)}
					>
						Filters{count > 0 ? ` ${count}` : ""}
					</button>
					<div className={`filters${filtersOpen ? " open" : ""}`}>
						{kind === "card" && (
							<div className="chips" role="group" aria-label="Type">
								{TYPES.map((type) => (
									<button
										key={type}
										type="button"
										className={`chip-toggle${view.types.includes(type) ? " on" : ""}`}
										aria-pressed={view.types.includes(type)}
										onClick={() => toggleType(type)}
									>
										{type}
									</button>
								))}
							</div>
						)}
						{kind === "card" && (
							<select value={view.epic} onChange={(event) => update({ epic: event.target.value })} aria-label="Epic">
								<option value="">All epics</option>
								{epics.map((epic) => (
									<option key={epic.id} value={epic.id}>
										{epic.name}
									</option>
								))}
							</select>
						)}
						{kind === "card" && (
							<div className="chips">
								{TOGGLES.map(([key, label]) => (
									<button
										key={key}
										type="button"
										className={`chip-toggle${view[key] ? " on" : ""}`}
										aria-pressed={view[key]}
										onClick={() => update({ [key]: !view[key] })}
									>
										{label}
									</button>
								))}
							</div>
						)}
					</div>
					<span className="spacer" />
					<button
						type="button"
						className={`chip-toggle${view.hideEmpty ? " on" : ""}`}
						aria-pressed={view.hideEmpty}
						onClick={() => update({ hideEmpty: !view.hideEmpty })}
					>
						Hide empty
					</button>
					<select
						value={view.sort}
						onChange={(event) => update({ sort: event.target.value as Sort })}
						aria-label="Sort"
					>
						<option value="manual">Manual</option>
						<option value="newest">Newest</option>
						<option value="oldest">Oldest</option>
						{kind === "card" && <option value="complexity">Complexity</option>}
						<option value="moved">Last moved</option>
					</select>
					<span className="tally">
						{visible.length}/{stubs.length}
					</span>
					{count > 0 && (
						<button
							type="button"
							className="quiet"
							onClick={() =>
								update({
									query: "",
									types: [],
									epic: "",
									blocked: false,
									claimed: false,
								})
							}
						>
							Clear {count}
						</button>
					)}
				</div>

				<NoticeBar notice={open && notice?.id === open.id ? null : notice} onDismiss={() => setNotice(null)} />

				<div className="workspace">
					<DndContext
						id={dndId}
						sensors={sensors}
						collisionDetection={collisions}
						onDragStart={onDragStart}
						onDragEnd={onDragEnd}
						onDragCancel={() => setDragging(null)}
					>
						{view.layout === "board" ? (
							<div className="lanes">
								{columns.map((column) => (
									<Lane key={column} {...groupProps(column)} />
								))}
							</div>
						) : (
							<div className="list">
								{columns.map((column) => (
									<ListGroup key={column} {...groupProps(column)} />
								))}
							</div>
						)}
						<DragOverlay dropAnimation={null}>
							{dragging && (
								<div className="card overlay">
									<CardBody stub={dragging} />
								</div>
							)}
						</DragOverlay>
						{open && (
							<Peek
								stub={open}
								kind={kind}
								cards={children[open.id] ?? []}
								lists={lists}
								handlers={handlersFor(open)}
								notice={notice?.id === open.id ? notice : null}
								onDismiss={() => setNotice(null)}
								onClose={() => setOpenId(null)}
							/>
						)}
					</DndContext>
				</div>
				<UndoToast toast={toast} busy={undoing} onUndo={undo} onDismiss={() => setToast(null)} />
			</div>
		</Names.Provider>
	);
}
