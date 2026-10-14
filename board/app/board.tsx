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
import { dropCard, editCard } from "@/app/actions";
import { Content } from "@/app/content";
import { boardColumns, FIBONACCI, type Kind, type Named, phaseOf, type Card as Stub } from "@/lib/shared";

const Names = createContext<Record<string, string>>({});

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
const TYPES = ["Feature", "Bug", "Timebox"] as const;
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
				<EpicPill epic={stub.epic} />
			</span>
		</>
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

function Lane({
	column,
	stubs,
	collapsed,
	onToggle,
	pending,
	onOpen,
}: {
	column: string;
	stubs: Stub[];
	collapsed: boolean;
	onToggle: () => void;
	pending: Set<string>;
	onOpen: (id: string) => void;
}) {
	const { setNodeRef, isOver } = useDroppable({ id: column });
	return (
		<section ref={setNodeRef} className={`lane${collapsed ? " collapsed" : ""}${isOver ? " over" : ""}`}>
			<button type="button" className="lane-head" onClick={onToggle} aria-expanded={!collapsed}>
				<StatusDot status={column} />
				<span className="lane-name">{column}</span>
				<span className="count">{stubs.length}</span>
			</button>
			{!collapsed && (
				<ul>
					{stubs.map((stub) => (
						<Card key={stub.id} stub={stub} pending={pending.has(stub.id)} onOpen={onOpen} />
					))}
				</ul>
			)}
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
}: {
	column: string;
	stubs: Stub[];
	collapsed: boolean;
	onToggle: () => void;
	pending: Set<string>;
	onOpen: (id: string) => void;
}) {
	const { setNodeRef, isOver } = useDroppable({ id: column });
	return (
		<section ref={setNodeRef} className={`group${isOver ? " over" : ""}`}>
			<button type="button" className="group-head" onClick={onToggle} aria-expanded={!collapsed}>
				<span className="caret">{collapsed ? "▸" : "▾"}</span>
				<StatusDot status={column} />
				<span className="lane-name">{column}</span>
				<span className="count">{stubs.length}</span>
			</button>
			{!collapsed && (
				<ul>
					{stubs.map((stub) => (
						<ListRow key={stub.id} stub={stub} pending={pending.has(stub.id)} onOpen={onOpen} />
					))}
				</ul>
			)}
		</section>
	);
}

function Ids({ ids, onOpen }: { ids?: string[]; onOpen: (id: string) => void }) {
	if (!ids || ids.length === 0) return <span className="empty">None</span>;
	return (
		<>
			{ids.map((id) => (
				<button key={id} type="button" className="ident-link" onClick={() => onOpen(id)}>
					{id}
				</button>
			))}
		</>
	);
}

function Peek({
	stub,
	kind,
	cards,
	onClose,
	onMove,
	onEdit,
	onOpen,
}: {
	stub: Stub;
	kind: Kind;
	cards: (Named & { status: string })[];
	onClose: () => void;
	onMove: (id: string, column: string) => void;
	onEdit: (id: string, field: string, value: string) => void;
	onOpen: (id: string) => void;
}) {
	const names = useContext(Names);
	const columns = boardColumns(kind);
	const dates = Object.entries(stub.dates ?? {}).sort(([, a], [, b]) => a.localeCompare(b));
	return (
		<aside className="peek" aria-label={`${stub.id} details`}>
			<header className="peek-head">
				<span className="ident">{stub.id}</span>
				<span className="peek-actions">
					<Link href={`/card/${stub.id}`} className="quiet-link">
						Open
					</Link>
					<button type="button" className="quiet" onClick={onClose} aria-label="Close">
						Esc
					</button>
				</span>
			</header>
			<h2 className="peek-title">{stub.name}</h2>
			<dl className="props">
				<dt>Status</dt>
				<dd>
					<select value={stub.status} onChange={(event) => onMove(stub.id, event.target.value)}>
						{!columns.includes(stub.status) && <option disabled>{stub.status}</option>}
						{columns.map((column) => (
							<option key={column}>{column}</option>
						))}
					</select>
				</dd>
				{kind === "card" && (
					<>
						<dt>Type</dt>
						<dd>
							<select value={stub.type} onChange={(event) => onEdit(stub.id, "type", event.target.value)}>
								{TYPES.map((type) => (
									<option key={type}>{type}</option>
								))}
							</select>
						</dd>
						<dt>Complexity</dt>
						<dd>
							<select
								value={stub.complexity ?? ""}
								onChange={(event) => onEdit(stub.id, "complexity", event.target.value)}
							>
								<option value="" disabled>
									Not set
								</option>
								{FIBONACCI.map((points) => (
									<option key={points} value={points}>
										{points}
									</option>
								))}
							</select>
						</dd>
						<dt>Epic</dt>
						<dd>
							{stub.epic ? (
								<Link href={`/epics?open=${stub.epic}`}>{names[stub.epic] ?? stub.epic}</Link>
							) : (
								<span className="empty">None</span>
							)}
						</dd>
						<dt>Blocked</dt>
						<dd>{stub.blocked ?? <span className="empty">No</span>}</dd>
					</>
				)}
				<dt>Claimed by</dt>
				<dd>{stub.session ?? <span className="empty">Nobody</span>}</dd>
				{kind === "card" && (
					<>
						<dt>Dependent on</dt>
						<dd>
							<Ids ids={stub.dependent_on} onOpen={onOpen} />
						</dd>
						<dt>Dependency for</dt>
						<dd>
							<Ids ids={stub.dependency_for} onOpen={onOpen} />
						</dd>
					</>
				)}
				{stub.prs && (
					<>
						<dt>PRs</dt>
						<dd className="wrap">{stub.prs}</dd>
					</>
				)}
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
	epics = [],
	children = {},
}: {
	initial: Stub[];
	kind?: Kind;
	epics?: Named[];
	children?: Record<string, (Named & { status: string })[]>;
}) {
	const router = useRouter();
	const [stubs, setStubs] = useState(initial);
	const [view, setView] = useState<View>({ ...DEFAULT_VIEW, collapsed: COLLAPSED[kind] });
	const [loaded, setLoaded] = useState(false);
	const [dragging, setDragging] = useState<Stub | null>(null);
	const [pending, setPending] = useState<Set<string>>(new Set());
	const [notice, setNotice] = useState("");
	const [openId, setOpenId] = useState<string | null>(null);
	const [filtersOpen, setFiltersOpen] = useState(false);
	const [, startTransition] = useTransition();
	const search = useRef<HTMLInputElement>(null);
	const dndId = useId();

	useEffect(() => setStubs(initial), [initial]);

	useEffect(() => {
		const saved = loadView(kind);
		const params = new URLSearchParams(window.location.search);
		const epic = params.get("epic");
		if (saved || epic) setView({ ...(saved ?? DEFAULT_VIEW), ...(epic ? { epic } : {}) });
		const opening = params.get("open");
		if (opening) setOpenId(opening);
		setLoaded(true);
	}, []);

	useEffect(() => {
		if (loaded) saveView(kind, view);
	}, [view, loaded]);

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

	function apply(id: string, optimistic: Partial<Stub>, request: () => Promise<{ record?: Stub; error?: string }>) {
		const before = stubs.find((s) => s.id === id);
		if (!before) return;
		setNotice("");
		setStubs((current) => current.map((s) => (s.id === id ? { ...s, ...optimistic } : s)));
		markPending(id, true);
		startTransition(async () => {
			const result = await request();
			markPending(id, false);
			if (result.error) {
				setStubs((current) => current.map((s) => (s.id === id ? before : s)));
				setNotice(`${id}: ${result.error}`);
				return;
			}
			const fresh = result.record;
			if (fresh) setStubs((current) => current.map((s) => (s.id === id ? fresh : s)));
			router.refresh();
		});
	}

	function move(id: string, column: string, rank?: number) {
		const stub = stubs.find((s) => s.id === id);
		if (!stub || (stub.status === column && rank === undefined)) return;
		apply(id, rank === undefined ? { status: column } : { status: column, rank }, () => dropCard(id, column, rank));
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

	function edit(id: string, field: string, value: string) {
		const optimistic = field === "complexity" ? { complexity: Number(value) } : { [field]: value };
		apply(id, optimistic as Partial<Stub>, () => editCard(id, field, value));
	}

	function onDragStart(event: DragStartEvent) {
		setDragging(stubs.find((stub) => stub.id === event.active.id) ?? null);
	}

	function onDragEnd(event: DragEndEvent) {
		setDragging(null);
		if (!event.over) return;
		const id = String(event.active.id);
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

				{notice && (
					<p className="notice error" role="alert">
						<span>{notice}</span>
						<button type="button" className="quiet" onClick={() => setNotice("")}>
							Dismiss
						</button>
					</p>
				)}

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
					</DndContext>
					{open && (
						<Peek
							stub={open}
							kind={kind}
							cards={children[open.id] ?? []}
							onClose={() => setOpenId(null)}
							onMove={move}
							onEdit={edit}
							onOpen={setOpenId}
						/>
					)}
				</div>
			</div>
		</Names.Provider>
	);
}
