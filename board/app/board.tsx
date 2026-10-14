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
import {
	type Bulk,
	bulkChange,
	createCard,
	dropCard,
	editCard,
	findInContent,
	linkCards,
	type Span,
	undoChange,
} from "@/app/actions";
import { cardCommands, type Edits, epicPage, movePage, recordCommands, themeCommands } from "@/app/commands";
import { Content } from "@/app/content";
import { Fields, type Handlers, Links, type Lists, linkChange, Title } from "@/app/fields";
import { cardLink, copyText, type Shortcut, ShortcutHelp, useKeys } from "@/app/keys";
import { MentionContext, type Mentions, mentionNames } from "@/app/markdown";
import { type Command, type Page, Palette } from "@/app/palette";
import { toastOf, typingIn, type Undoable, UndoToast, undoable, withNewId } from "@/app/toast";
import {
	COLLAPSED,
	DEFAULT_VIEW,
	type Found,
	type Layout,
	loadView,
	matches,
	type Sort,
	saveView,
	sorter,
	TOGGLES,
	type View,
} from "@/app/view";
import {
	boardColumns,
	bounces,
	contentSearchFailed,
	dueState,
	fieldName,
	type Kind,
	kindOf,
	manualRank,
	type Named,
	overrunTitle,
	phaseOf,
	showsOverrun,
	SPLIT_ABOVE,
	type Card as Stub,
	TYPES,
} from "@/lib/shared";

const Names = createContext<Record<string, string>>({});

type Notice = { id: string; text: string } | null;

const SEARCH_NOTICE = "search";

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

const effectiveRank = manualRank;

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

function filterCount(view: View) {
	return [view.query.trim() !== "", view.types.length > 0, view.epic !== "", view.blocked, view.claimed].filter(Boolean)
		.length;
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

function Complexity({ stub }: { stub: Stub }) {
	if (stub.complexity == null) return null;
	const split = stub.complexity > SPLIT_ABOVE;
	return (
		<span
			className={`pill${split ? " split" : ""}`}
			title={split ? `${stub.complexity} points, above the ${SPLIT_ABOVE} a day holds - split it?` : `${stub.complexity} points`}
		>
			{stub.complexity}
		</span>
	);
}

function Signals({ stub }: { stub: Stub }) {
	const back = bounces(stub);
	const total = back.reduce((sum, [, count]) => sum + count, 0);
	return (
		<>
			{stub.type === "Timebox" && stub.timebox_mins != null && (
				<span className="pill" title={`A timebox of ${stub.timebox_mins} minutes`}>
					{stub.timebox_mins}m
				</span>
			)}
			{showsOverrun(stub) && (
				<span className="pill overrun" title={overrunTitle(stub)}>
					Overrunning
				</span>
			)}
			{total > 0 && (
				<span
					className="pill rework"
					title={`Back from ${back.map(([gate, count]) => `${gate} ${count === 1 ? "once" : `${count} times`}`).join(", ")}`}
				>
					↺ {total}
				</span>
			)}
		</>
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
				<Complexity stub={stub} />
				{stub.blocked && <span className="pill blocked">Blocked</span>}
				<Signals stub={stub} />
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

type ItemProps = {
	stub: Stub;
	pending: boolean;
	focused: boolean;
	selected: boolean;
	onOpen: (id: string, toggle: boolean) => void;
};

function Card({ stub, pending, focused, selected, onOpen }: ItemProps) {
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
				data-card={stub.id}
				className={`card${pending ? " pending" : ""}${focused ? " focused" : ""}${selected ? " selected" : ""}`}
				aria-pressed={selected || undefined}
				onClick={(event) => onOpen(stub.id, event.shiftKey || event.metaKey || event.ctrlKey)}
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
	focusedId,
	selected,
	onOpen,
	adding,
}: {
	column: string;
	stubs: Stub[];
	collapsed: boolean;
	onToggle: () => void;
	pending: Set<string>;
	focusedId: string | null;
	selected: Set<string>;
	onOpen: (id: string, toggle: boolean) => void;
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
						<Card
							key={stub.id}
							stub={stub}
							pending={pending.has(stub.id)}
							focused={focusedId === stub.id}
							selected={selected.has(stub.id)}
							onOpen={onOpen}
						/>
					))}
				</ul>
			)}
			{!collapsed && <QuickAdd column={column} {...adding} />}
		</section>
	);
}

function ListRow({ stub, pending, focused, selected, onOpen }: ItemProps) {
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
				data-card={stub.id}
				className={`row${pending ? " pending" : ""}${focused ? " focused" : ""}${selected ? " selected" : ""}`}
				aria-pressed={selected || undefined}
				onClick={(event) => onOpen(stub.id, event.shiftKey || event.metaKey || event.ctrlKey)}
			>
				<span className="ident">{stub.id}</span>
				<StatusDot status={stub.status} />
				<span className="name">{stub.name}</span>
				<span className="row-meta">
					{stub.blocked && <span className="pill blocked">Blocked</span>}
					<Signals stub={stub} />
					<DueChip stub={stub} />
					<EpicPill epic={stub.epic} />
					{stub.type && <TypeMark type={stub.type} />}
					<span
						className={`points${(stub.complexity ?? 0) > SPLIT_ABOVE ? " split" : ""}`}
						title={(stub.complexity ?? 0) > SPLIT_ABOVE ? `Above the ${SPLIT_ABOVE} a day holds - split it?` : undefined}
					>
						{stub.complexity ?? ""}
					</span>
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
	focusedId,
	selected,
	onOpen,
	adding,
}: {
	column: string;
	stubs: Stub[];
	collapsed: boolean;
	onToggle: () => void;
	pending: Set<string>;
	focusedId: string | null;
	selected: Set<string>;
	onOpen: (id: string, toggle: boolean) => void;
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
						<ListRow
							key={stub.id}
							stub={stub}
							pending={pending.has(stub.id)}
							focused={focusedId === stub.id}
							selected={selected.has(stub.id)}
							onOpen={onOpen}
						/>
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
	onCopy,
}: {
	stub: Stub;
	kind: Kind;
	cards: (Named & { status: string })[];
	lists: Lists;
	handlers: Handlers;
	notice: Notice;
	onDismiss: () => void;
	onClose: () => void;
	onCopy: () => void;
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
					<button type="button" className="quiet" onClick={onCopy} title="Copy link (Cmd/Ctrl+Shift+.)">
						Copy link
					</button>
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

function BulkBar({
	kind,
	count,
	lists,
	columns,
	edits,
	onClear,
}: {
	kind: Kind;
	count: number;
	lists: Lists;
	columns: string[];
	edits: Edits;
	onClear: () => void;
}) {
	const pick = (apply: (value: string) => void) => (event: React.ChangeEvent<HTMLSelectElement>) => {
		const value = event.target.value;
		event.target.value = "-";
		if (value !== "-") apply(value);
	};
	return (
		<div className="bulk" role="toolbar" aria-label={`${count} selected`}>
			<span className="bulk-count">{count} selected</span>
			<select aria-label="Move the selected cards" defaultValue="-" onChange={pick(edits.move)}>
				<option value="-" disabled>
					Move to…
				</option>
				{columns.map((column) => (
					<option key={column}>{column}</option>
				))}
			</select>
			{kind === "card" && (
				<>
					<select
						aria-label="Set the epic of the selected cards"
						defaultValue="-"
						onChange={pick((epic) => edits.edit("epic", epic, { epic: epic || null }))}
					>
						<option value="-" disabled>
							Epic…
						</option>
						<option value="">No epic</option>
						{lists.epics.map((epic) => (
							<option key={epic.id} value={epic.id}>
								{epic.name}
							</option>
						))}
					</select>
					<select
						aria-label="Set the type of the selected cards"
						defaultValue="-"
						onChange={pick((type) => edits.edit("type", type, { type: type as Stub["type"] }))}
					>
						<option value="-" disabled>
							Type…
						</option>
						{TYPES.map((type) => (
							<option key={type}>{type}</option>
						))}
					</select>
					<select
						aria-label="Set the sprint of the selected cards"
						defaultValue="-"
						onChange={pick((sprint) => edits.edit("sprint", sprint, { sprint: sprint || null }))}
					>
						<option value="-" disabled>
							Sprint…
						</option>
						<option value="">No sprint</option>
						{lists.sprints.map((sprint) => (
							<option key={sprint.id} value={sprint.id}>
								{sprint.name}
							</option>
						))}
					</select>
				</>
			)}
			<button type="button" className="quiet" onClick={() => edits.archive?.()}>
				Archive
			</button>
			<button type="button" className="quiet" onClick={onClear} title="Clear the selection (Esc)">
				Clear
			</button>
		</div>
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
	const [focusedId, setFocusedId] = useState<string | null>(null);
	const [helpOpen, setHelpOpen] = useState(false);
	const [palette, setPalette] = useState<Page | null>(null);
	const [selected, setSelected] = useState<Set<string>>(new Set());
	const [inContent, setInContent] = useState<{ query: string; ids: Set<string> } | null>(null);
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

	const sensors = useSensors(
		useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
		useSensor(TouchSensor, { activationConstraint: { delay: 220, tolerance: 6 } }),
		useSensor(KeyboardSensor),
	);

	const names = useMemo(() => Object.fromEntries(epics.map((epic) => [epic.id, epic.name])), [epics]);
	const query = view.query.trim();
	const found = useMemo<Found>(
		() => ({ names, inContent: inContent?.query === query ? inContent.ids : undefined }),
		[names, inContent, query],
	);

	useEffect(() => {
		if (query.length < 2) return;
		let live = true;
		const timer = window.setTimeout(async () => {
			const result = await findInContent(kind, query);
			if (!live) return;
			if ("ids" in result) {
				setInContent({ query, ids: new Set(result.ids) });
				setNotice((current) => (current?.id === SEARCH_NOTICE ? null : current));
			} else setNotice({ id: SEARCH_NOTICE, text: contentSearchFailed(kind, result.error) });
		}, 200);
		return () => {
			live = false;
			window.clearTimeout(timer);
		};
	}, [query, kind, initial]);

	const mentions = useMemo<Mentions>(() => {
		const nameOf = mentionNames([...lists.cards, ...lists.epics, ...stubs]);
		return {
			nameOf,
			onOpen: (id) => {
				if (kindOf(id) !== kind) return false;
				const number = id.split("-").at(-1);
				const found =
					stubs.find((stub) => stub.id === id) ??
					stubs.find((stub) => kindOf(stub.id) === kind && stub.id.split("-").at(-1) === number);
				if (!found) return false;
				setOpenId(found.id);
				setFocusedId(found.id);
				return true;
			},
		};
	}, [lists.cards, lists.epics, stubs, kind]);

	const columnsOfKind = boardColumns(kind);
	const visible = useMemo(
		() => stubs.filter((stub) => matches(stub, view, found)).sort(sorter(view.sort)),
		[stubs, view, found],
	);
	const columns = useMemo(() => {
		const extra = [...new Set(stubs.map((stub) => stub.status))].filter((status) => !columnsOfKind.includes(status));
		const all = [...columnsOfKind, ...extra];
		return view.hideEmpty ? all.filter((column) => visible.some((stub) => stub.status === column)) : all;
	}, [stubs, visible, view.hideEmpty, columnsOfKind]);
	const open = openId ? (stubs.find((stub) => stub.id === openId) ?? null) : null;
	const order = useMemo(
		() =>
			columns
				.filter((column) => !view.collapsed.includes(column))
				.flatMap((column) => visible.filter((stub) => stub.status === column)),
		[columns, visible, view.collapsed],
	);

	useEffect(() => {
		if (!focusedId) return;
		document
			.querySelector(`[data-card="${CSS.escape(focusedId)}"]`)
			?.scrollIntoView({ block: "nearest", inline: "nearest" });
	}, [focusedId]);

	function openCard(id: string | null) {
		setOpenId(id);
		if (id) setFocusedId(id);
	}

	function toggleSelected(id: string) {
		setFocusedId(id);
		setSelected((current) => {
			const next = new Set(current);
			if (next.has(id)) next.delete(id);
			else next.add(id);
			return next;
		});
	}

	function clickCard(id: string, toggle: boolean) {
		if (toggle || chosen.length > 0) toggleSelected(id);
		else openCard(id);
	}

	const chosen = [...selected].filter((id) => order.some((stub) => stub.id === id));

	useEffect(() => {
		setSelected((current) => {
			const kept = [...current].filter((id) => order.some((stub) => stub.id === id));
			return kept.length === current.size ? current : new Set(kept);
		});
	}, [order]);

	function targets() {
		if (chosen.length > 0) return chosen;
		const target = openId ?? focusedId;
		return target && stubs.some((stub) => stub.id === target) ? [target] : [];
	}

	function runBulk(ids: string[], change: Bulk, optimistic: Partial<Stub> | null, label: string) {
		if (ids.length === 0) return;
		const before = stubs.filter((stub) => ids.includes(stub.id));
		setNotice(null);
		setToast(null);
		setStubs((current) =>
			optimistic === null
				? current.filter((stub) => !ids.includes(stub.id))
				: current.map((stub) => (ids.includes(stub.id) ? { ...stub, ...optimistic } : stub)),
		);
		for (const id of ids) markPending(id, true);
		startTransition(async () => {
			const result = await bulkChange(ids, change);
			for (const id of ids) markPending(id, false);
			const done = new Map(result.records.map(({ from, record }) => [from, record]));
			setStubs((current) => {
				const kept = current.filter((stub) => !ids.includes(stub.id));
				const back = before.flatMap((stub) => {
					if (!done.has(stub.id)) return [stub];
					const record = done.get(stub.id);
					return record ? [record] : [];
				});
				return [...kept, ...back];
			});
			const renamed = new Map(result.records.flatMap(({ from, record }) => (record ? [[from, record.id]] : [])));
			setOpenId((opened) => (opened && done.has(opened) ? (done.get(opened)?.id ?? null) : opened));
			setSelected(
				(current) =>
					new Set([...current].map((id) => renamed.get(id) ?? id).filter((id) => !done.has(id) || done.get(id))),
			);
			if (result.errors.length > 0) setNotice({ id: "", text: result.errors.join("; ") });
			const count = result.records.length;
			if (count > 0)
				setToast(
					toastOf(
						count === 1
							? withNewId(
									label.replace("{n}", result.records[0].from),
									result.records[0].from,
									result.records[0].record?.id ?? result.records[0].from,
								)
							: label.replace("{n}", `${count} ${kind}s`),
						result.undo,
					),
				);
			router.refresh();
		});
	}

	function bulkEdits(ids: string[]): Edits {
		return {
			label: ids.length === 1 ? ids[0] : `${ids.length} ${kind}s`,
			move: (column) => runBulk(ids, { op: "move", column }, { status: column }, `Moved {n} to ${column}`),
			edit: (field, value, change) =>
				runBulk(ids, { op: "set", field, value }, change, `Changed the ${fieldName(field)} of {n}`),
			archive: () => runBulk(ids, { op: "archive" }, null, "Archived {n}"),
		};
	}

	function step(by: number) {
		if (order.length === 0) return;
		const from = order.findIndex((stub) => stub.id === (focusedId ?? openId));
		const index = from < 0 ? (by > 0 ? 0 : order.length - 1) : Math.min(order.length - 1, Math.max(0, from + by));
		const id = order[index].id;
		setFocusedId(id);
		if (openId) setOpenId(id);
	}

	function stepColumn(by: number) {
		const current = order.find((stub) => stub.id === (focusedId ?? openId));
		const shown = columns.filter((column) => order.some((stub) => stub.status === column));
		if (shown.length === 0) return;
		const from = current ? shown.indexOf(current.status) : -1;
		const column = shown[Math.min(shown.length - 1, Math.max(0, from < 0 ? 0 : from + by))];
		const id = order.find((stub) => stub.status === column)?.id;
		if (!id) return;
		setFocusedId(id);
		if (openId) setOpenId(id);
	}

	async function copy(id: string, asLink: boolean) {
		const copied = await copyText(asLink ? cardLink(id) : id);
		setToast(toastOf(copied ? `Copied ${asLink ? `the link to ${id}` : id}` : `Could not copy ${id}`));
	}

	function editsFor(ids: string[]): Edits | null {
		if (ids.length === 0) return null;
		if (ids.length > 1) return bulkEdits(ids);
		const stub = stubs.find((s) => s.id === ids[0]);
		if (!stub) return null;
		const handlers = handlersFor(stub);
		return { label: stub.id, move: handlers.onMove, edit: handlers.onEdit, archive: bulkEdits(ids).archive };
	}

	function rootPage(): Page {
		const ids = targets();
		const record = ids.length === 1 ? (stubs.find((stub) => stub.id === ids[0]) ?? null) : null;
		const edits = editsFor(ids);
		const actions: Command[] = [...recordCommands(edits ? kind : null, record, lists, edits)];
		if (chosen.length > 0) {
			actions.push({
				id: "do:unselect",
				group: edits?.label,
				label: "Clear the selection",
				hint: "Esc",
				run: () => setSelected(new Set()),
			});
		} else if (record) {
			actions.push({
				id: "do:select",
				group: record.id,
				label: "Select it, to change several cards at once",
				hint: "X",
				run: () => toggleSelected(record.id),
			});
		}
		if (record && chosen.length === 0) {
			actions.push(
				{ id: "do:copy", group: record.id, label: "Copy id", hint: "Cmd/Ctrl+.", run: () => copy(record.id, false) },
				{ id: "do:link", group: record.id, label: "Copy link", run: () => copy(record.id, true) },
				{ id: "do:page", group: record.id, label: "Open its page", run: () => router.push(`/card/${record.id}`) },
			);
		}
		const general: Command[] = [
			{
				id: "go:new",
				group: "Board",
				label: `New ${kind}…`,
				hint: "C",
				next: () => ({
					title: `New ${kind} in`,
					items: columns.map((column) => ({
						id: `new:${column}`,
						label: column,
						run: () => {
							if (view.collapsed.includes(column)) toggleColumn(column);
							setAddingIn(column);
						},
					})),
				}),
			},
			{
				id: "go:layout",
				group: "Board",
				label: view.layout === "board" ? "Show as a list" : "Show as a board",
				run: () => update({ layout: view.layout === "board" ? "list" : "board" }),
			},
			{
				id: "go:other",
				group: "Board",
				label: kind === "card" ? "Go to epics" : "Go to cards",
				run: () => router.push(kind === "card" ? "/epics" : "/"),
			},
			{ id: "go:search", group: "Board", label: "Search the board", hint: "/", run: () => search.current?.focus() },
			{ id: "go:keys", group: "Board", label: "Keyboard shortcuts", hint: "?", run: () => setHelpOpen(true) },
			...(filterCount(view) > 0
				? [{ id: "go:clear", group: "Board", label: "Clear the filters", run: clearFilters }]
				: []),
			...themeCommands(),
		];
		return { title: "Command menu", root: true, items: [...actions, ...general, ...cardCommands(stubs, openCard)] };
	}

	function clearFilters() {
		update({ query: "", types: [], epic: "", blocked: false, claimed: false });
	}

	useKeys((event) => {
		if (helpOpen || palette || event.defaultPrevented) return;
		const typing = typingIn(event.target);
		const command = event.metaKey || event.ctrlKey;
		const target = openId ?? focusedId;
		if (command && !event.shiftKey && event.key.toLowerCase() === "k") {
			event.preventDefault();
			setPalette(rootPage());
			return;
		}
		if (command && (event.code === "Period" || event.key === "." || event.key === ">")) {
			if (!target || typing) return;
			event.preventDefault();
			copy(target, event.shiftKey);
			return;
		}
		if (event.key === "Escape") {
			if (typing) (event.target as HTMLElement).blur();
			else if (openId) setOpenId(null);
			else if (chosen.length > 0) setSelected(new Set());
			else setFocusedId(null);
			return;
		}
		if (typing || command || event.altKey) return;
		const inPanel = event.target instanceof HTMLElement && event.target.closest(".peek") !== null;
		switch (event.key) {
			case "/":
				event.preventDefault();
				search.current?.focus();
				break;
			case "?":
				event.preventDefault();
				setHelpOpen(true);
				break;
			case "j":
			case "k":
				event.preventDefault();
				step(event.key === "j" ? 1 : -1);
				break;
			case "ArrowDown":
			case "ArrowUp":
				if (inPanel) return;
				event.preventDefault();
				step(event.key === "ArrowDown" ? 1 : -1);
				break;
			case "h":
			case "l":
				event.preventDefault();
				stepColumn(event.key === "h" ? -1 : 1);
				break;
			case "Enter":
			case "o": {
				const control =
					event.target instanceof HTMLElement && event.target.closest("button, a, summary, [role=dialog]");
				if (!focusedId || inPanel || (control && !(control as HTMLElement).dataset.card)) return;
				event.preventDefault();
				setOpenId(focusedId);
				break;
			}
			case "s":
			case "e": {
				const ids = targets();
				const edits = editsFor(ids);
				const record = ids.length === 1 ? stubs.find((stub) => stub.id === ids[0]) : undefined;
				if (!edits || (event.key === "e" && kind !== "card")) return;
				event.preventDefault();
				setPalette(event.key === "s" ? movePage(kind, record?.status, edits) : epicPage(lists, record?.epic, edits));
				break;
			}
			case "x":
				if (!focusedId) return;
				event.preventDefault();
				toggleSelected(focusedId);
				break;
			case "c": {
				event.preventDefault();
				const focused = order.find((stub) => stub.id === target);
				const column = focused?.status ?? columns.find((c) => !view.collapsed.includes(c)) ?? columns[0];
				if (!column) return;
				if (view.collapsed.includes(column)) toggleColumn(column);
				setAddingIn(column);
				break;
			}
		}
	});

	const shortcuts: Shortcut[] = [
		{ keys: ["j", "k"], label: "Next or previous card" },
		{ keys: ["h", "l"], label: "Previous or next column" },
		{ keys: ["Enter"], label: "Open the focused card" },
		{ keys: ["Esc"], label: "Close the card, or clear the focus" },
		{ keys: ["c"], label: "New card in the focused column" },
		{ keys: ["Cmd/Ctrl", "K"], label: "Command menu: jump to a card or run an action" },
		{ keys: ["x"], label: "Select the focused card, or Shift-click one" },
		{ keys: ["s"], label: "Move the card, or the selected cards, to a column" },
		...(kind === "card" ? [{ keys: ["e"], label: "Set the epic of the card, or the selected cards" }] : []),
		{ keys: ["/"], label: "Search" },
		{ keys: ["Cmd/Ctrl", "."], label: "Copy the card's id" },
		{ keys: ["Cmd/Ctrl", "Shift", "."], label: "Copy a link to the card" },
		{ keys: ["Cmd/Ctrl", "Z"], label: "Undo the last change" },
		{ keys: ["?"], label: "Show these shortcuts" },
	];

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
		request: () => Promise<{ record?: Stub; error?: string; moved?: string; undo?: Span }>,
		label: string,
	) {
		const before = stubs.find((s) => s.id === id);
		if (!before) return;
		setNotice(null);
		setToast(null);
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
				setToast(undoable(fresh.id, result.undo, withNewId(label, id, fresh.id)));
			}
			router.refresh();
		});
	}

	function undo(shown: Undoable) {
		setUndoing(true);
		setNotice(null);
		startTransition(async () => {
			const failures: string[] = [];
			for (const change of shown.changes) {
				const result = await undoChange(change.id, { since: change.since, until: change.until });
				if (result.error) {
					failures.push(result.error);
					continue;
				}
				const fresh = result.record;
				if (fresh) {
					setStubs((current) =>
						current.some((s) => s.id === change.id)
							? current.map((s) => (s.id === change.id ? fresh : s))
							: [...current, fresh],
					);
					if (fresh.id !== change.id) setOpenId((opened) => (opened === change.id ? fresh.id : opened));
				}
			}
			setUndoing(false);
			setToast((current) => (current?.key === shown.key ? null : current));
			if (failures.length > 0) setNotice({ id: "", text: `Could not undo: ${failures.join("; ")}` });
			router.refresh();
		});
	}

	function move(id: string, column: string, rank?: number) {
		const stub = stubs.find((s) => s.id === id);
		if (!stub || (stub.status === column && rank === undefined)) return;
		const label = stub.status === column ? `Reordered ${id} in ${column}` : `Moved ${id} to ${column}`;
		apply(
			id,
			rank === undefined ? { status: column } : { status: column, rank },
			() => dropCard(id, column, rank),
			label,
		);
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
		focusedId,
		selected,
		onOpen: clickCard,
		adding: {
			open: addingIn === column,
			onOpenChange: (open: boolean) => setAddingIn(open ? column : null),
			onCreate: (name: string) => create(column, name),
		},
	});

	return (
		<Names.Provider value={names}>
			<MentionContext.Provider value={mentions}>
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
					<button
						type="button"
						className="chip-toggle palette-open"
						onClick={() => setPalette(rootPage())}
						title="Command menu (Cmd/Ctrl+K)"
					>
						Commands
					</button>
					<button
						type="button"
						className="quiet shortcuts-open"
						onClick={() => setHelpOpen(true)}
						title="Keyboard shortcuts (?)"
					>
						?
					</button>
					<span className="tally">
						{visible.length}/{stubs.length}
					</span>
					{count > 0 && (
						<button type="button" className="quiet" onClick={clearFilters}>
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
								onCopy={() => copy(open.id, true)}
							/>
						)}
					</DndContext>
				</div>
				{chosen.length > 0 && (
					<BulkBar
						kind={kind}
						count={chosen.length}
						lists={lists}
						columns={columns}
						edits={bulkEdits(chosen)}
						onClear={() => setSelected(new Set())}
					/>
				)}
				<UndoToast toast={toast} busy={undoing} onUndo={undo} onDismiss={() => setToast(null)} />
				{helpOpen && <ShortcutHelp shortcuts={shortcuts} onClose={() => setHelpOpen(false)} />}
				{palette && <Palette start={palette} onClose={() => setPalette(null)} />}
			</div>
			</MentionContext.Provider>
		</Names.Provider>
	);
}
