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
import {
	createContext,
	type ReactNode,
	useContext,
	useEffect,
	useId,
	useMemo,
	useRef,
	useState,
	useTransition,
} from "react";
import {
	type Bulk,
	bulkChange,
	type Change,
	createCard,
	dropCard,
	type FieldSet,
	duplicateCard,
	editCard,
	findInContent,
	finishEpic,
	finishEpics,
	forgetView,
	linkCards,
	type Span,
	storeView,
	undoChange,
} from "@/app/actions";
import { Activity } from "@/app/activity";
import { cardCommands, type Edits, epicPage, movePage, recordCommands, themeCommands } from "@/app/commands";
import { Content, confirmDiscard } from "@/app/content";
import { type Draft, NewRecord } from "@/app/create";
import { EpicDoneDialog, EpicsDoneDialog, type Finishing, openTickets } from "@/app/epic-done";
import { ViewDialog, type ViewDialogAsk } from "@/app/view-dialog";
import { ChoiceSelect, type SearchOption } from "@/app/search-select";
import { Fields, type Handlers, Links, type Lists, linkChange, Title } from "@/app/fields";
import { cardLink, copyText, type Shortcut, ShortcutHelp, useKeys } from "@/app/keys";
import { MentionContext, type Mentions, mentionNames } from "@/app/markdown";
import { type Command, type Page, Palette } from "@/app/palette";
import { EstimateFacts, EstimatePill } from "@/app/estimates";
import { ProgressMeter } from "@/app/progress";
import { Stages } from "@/app/stages";
import { contextOf, LabelPills, nextTableSort, parseTableSort, sortTable, Table, tableColumns } from "@/app/table";
import { toastOf, typingIn, type Undoable, UndoToast, undoable, withNewId } from "@/app/toast";
import {
	collapsedIn,
	defaultView,
	choicePasses,
	chosen,
	droppedInto,
	keptIn,
	type FieldChange,
	type Found,
	GROUPINGS,
	type GroupContext,
	groupingOf,
	LAYOUTS,
	loadLastParent,
	loadView,
	restoredView,
	matches,
	NO_CHOICE,
	onlyEpic,
	type Sort,
	saveLastParent,
	saveView,
	sorter,
	type Swimlane,
	swimlanesOf,
	TOGGLES,
	toggledIn,
	type View,
} from "@/app/view";
import { type Progress, progressOf } from "@/lib/metrics";
import { type Estimates as EpicEstimates, estimatesOf } from "@/lib/plan";
import {
	boardColumns,
	bounces,
	contentSearchFailed,
	dueState,
	fieldName,
	type Kind,
	kindName,
	kindOf,
	manualRank,
	movedTo,
	type Named,
	overrunTitle,
	type SavedView,
	phaseOf,
	showsOverrun,
	SPLIT_ABOVE,
	type Card as Stub,
	TIMEBOXES,
	TYPES,
	timeboxText,
} from "@/lib/shared";

const HEADER_SORT = "header";

const AGING_AFTER = 3;

const AGED_AFTER = 5;

const Names = createContext<Record<string, string>>({});

const Progresses = createContext<Record<string, Progress>>({});
const Estimates = createContext<Record<string, EpicEstimates>>({});

function Rollups({
	progresses,
	estimates,
	children,
}: {
	progresses: Record<string, Progress>;
	estimates: Record<string, EpicEstimates>;
	children: ReactNode;
}) {
	return (
		<Progresses.Provider value={progresses}>
			<Estimates.Provider value={estimates}>{children}</Estimates.Provider>
		</Progresses.Provider>
	);
}

type Child = Named & Pick<Stub, "status" | "type" | "complexity" | "estimate" | "dependent_on">;

export type Notice = { id: string; text: string } | null;

const SEARCH_NOTICE = "search";

export function NoticeBar({ notice, onDismiss }: { notice: Notice; onDismiss: () => void }) {
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

function swimKey(swimlane: Swimlane) {
	return `swim:${swimlane.key}`;
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

function filterCount(view: View) {
	return [
		view.query.trim() !== "",
		view.types.length > 0,
		chosen(view.projects) > 0,
		chosen(view.epics) > 0,
		view.labels.length > 0,
		view.urgent,
		view.blocked,
		view.claimed,
		view.overrunning,
	].filter(Boolean).length;
}

function StatusDot({ status }: { status: string }) {
	return <span className={`dot phase-${phaseOf(status)}`} aria-hidden="true" />;
}

function TypeMark({ type }: { type: string }) {
	return <span className={`type type-${type.toLowerCase()}`}>{type}</span>;
}

function UrgentMark() {
	return (
		<span className="pill urgent" title="Urgent - picked before every other ticket">
			Urgent
		</span>
	);
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
		<span className={`pill due due-${due.tone}${due.held ? " held" : ""}`} title={due.title} suppressHydrationWarning>
			{due.label}
			{due.held && " · target"}
		</span>
	);
}

function Complexity({ stub }: { stub: Stub }) {
	if (stub.complexity == null) return null;
	const split = stub.complexity > SPLIT_ABOVE;
	return (
		<span
			className={`pill${split ? " split" : ""}`}
			title={
				split
					? `${stub.complexity} points, above the ${SPLIT_ABOVE} a day holds - split it?`
					: `${stub.complexity} points`
			}
		>
			{stub.complexity}
		</span>
	);
}

function DaysInColumn({ stub }: { stub: Stub }) {
	const days = stub.days_in_column ?? 0;
	if (days < 1) return null;
	const tone = days >= AGED_AFTER ? " aged" : days >= AGING_AFTER ? " aging" : "";
	return (
		<span className={`pill days${tone}`} title={`${days} working ${days === 1 ? "day" : "days"} in ${stub.status}`}>
			{days}d
		</span>
	);
}

function Signals({ stub }: { stub: Stub }) {
	const back = bounces(stub);
	const total = back.reduce((sum, [, count]) => sum + count, 0);
	const progress = useContext(Progresses)[stub.id];
	const estimates = useContext(Estimates)[stub.id];
	return (
		<>
			{progress && progress.total > 0 && <ProgressMeter progress={progress} />}
			{estimates && <EstimatePill estimates={estimates} />}
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
			<DaysInColumn stub={stub} />
			{(stub.comments ?? 0) > 0 && (
				<span
					className="pill comments"
					title={`${stub.comments} open comment ${stub.comments === 1 ? "thread" : "threads"}`}
				>
					<svg viewBox="0 0 16 16" aria-hidden="true">
						<path d="M3 3.5h10a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1H8l-3 2.5v-2.5H3a1 1 0 0 1-1-1v-6a1 1 0 0 1 1-1z" />
					</svg>
					{stub.comments}
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
				{stub.urgent && <UrgentMark />}
				{stub.session && <span className="claimed" title={`Claimed by ${stub.session}`} />}
			</span>
			<span className="name">
				{stub.icon && <span className="record-icon">{stub.icon}</span>}
				{stub.name}
			</span>
			<span className="meta">
				{stub.type && <TypeMark type={stub.type} />}
				<Complexity stub={stub} />
				{stub.blocked && <span className="pill blocked">Blocked</span>}
				<Signals stub={stub} />
				<DueChip stub={stub} />
				<EpicPill epic={stub.epic} />
				<LabelPills labels={stub.labels} />
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

function LaneCount({ shown, total }: { shown: number; total: number }) {
	const hidden = total - shown;
	return (
		<span className="count" title={hidden > 0 ? `${shown} shown, ${hidden} hidden by the filters` : undefined}>
			{shown}
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

function Lane({
	column,
	dropId,
	stubs,
	total,
	collapsed,
	onToggle,
	pending,
	focusedId,
	selected,
	onOpen,
	dock,
}: {
	column: string;
	dropId?: string;
	stubs: Stub[];
	total: number;
	collapsed: boolean;
	onToggle: () => void;
	pending: Set<string>;
	focusedId: string | null;
	selected: Set<string>;
	onOpen: (id: string, toggle: boolean) => void;
	dock?: ReactNode;
}) {
	const { setNodeRef, isOver } = useDroppable({ id: dropId ?? column });
	return (
		<section
			ref={setNodeRef}
			className={`lane${collapsed ? " collapsed" : ""}${isOver ? " over" : ""}`}
		>
			<button type="button" className="lane-head" onClick={onToggle} aria-expanded={!collapsed}>
				<StatusDot status={column} />
				<span className="lane-name">{column}</span>
				<LaneCount shown={stubs.length} total={total} />
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
			{dock}
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
				<span className="name">
					{stub.icon && <span className="record-icon">{stub.icon}</span>}
					{stub.name}
				</span>
				<span className="row-meta">
					{stub.urgent && <UrgentMark />}
					{stub.blocked && <span className="pill blocked">Blocked</span>}
					<Signals stub={stub} />
					<DueChip stub={stub} />
					<EpicPill epic={stub.epic} />
					<LabelPills labels={stub.labels} />
					{stub.type && <TypeMark type={stub.type} />}
					<span
						className={`points${(stub.complexity ?? 0) > SPLIT_ABOVE ? " split" : ""}`}
						title={
							(stub.complexity ?? 0) > SPLIT_ABOVE ? `Above the ${SPLIT_ABOVE} a day holds - split it?` : undefined
						}
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
	dropId,
	stubs,
	total,
	collapsed,
	onToggle,
	pending,
	focusedId,
	selected,
	onOpen,
	dock,
}: {
	column: string;
	dropId?: string;
	stubs: Stub[];
	total: number;
	collapsed: boolean;
	onToggle: () => void;
	pending: Set<string>;
	focusedId: string | null;
	selected: Set<string>;
	onOpen: (id: string, toggle: boolean) => void;
	dock?: ReactNode;
}) {
	const { setNodeRef, isOver } = useDroppable({ id: dropId ?? column });
	return (
		<section ref={setNodeRef} className={`group${isOver ? " over" : ""}`}>
			<button type="button" className="group-head" onClick={onToggle} aria-expanded={!collapsed}>
				<span className="caret">{collapsed ? "▸" : "▾"}</span>
				<StatusDot status={column} />
				<span className="lane-name">{column}</span>
				<LaneCount shown={stubs.length} total={total} />
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
			{dock}
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
	onSaved,
	onDuplicate,
	onArchive,
}: {
	stub: Stub;
	kind: Kind;
	cards: Child[];
	lists: Lists;
	handlers: Handlers;
	notice: Notice;
	onDismiss: () => void;
	onClose: () => void;
	onCopy: () => void;
	onSaved: (record: Stub, undo?: Span, label?: string) => void;
	onDuplicate: () => void;
	onArchive: () => void;
}) {
	const panel = useRef<HTMLElement>(null);
	const number = stub.id.split("-").at(-1);
	const [tab, setTab] = useState<"details" | "history">("details");
	useEffect(() => {
		panel.current?.scrollTo({ top: 0 });
	}, [number]);
	return (
		<aside className="peek" ref={panel} aria-label={`${stub.id} details`}>
			<header className="peek-head">
				<PanelHandle id={stub.id} />
				<span className="peek-actions">
					<button type="button" className="quiet peek-copy" onClick={onCopy} title="Copy link (Cmd/Ctrl+Shift+.)">
						Copy link
					</button>
					<button type="button" className="quiet" onClick={onDuplicate} title="Make a copy of it in the first column">
						Duplicate
					</button>
					<button
						type="button"
						className="quiet"
						onClick={onArchive}
						title="Take it off the board - bring it back from the Archive page"
					>
						Archive
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
			{stub.icon && <span className="page-icon">{stub.icon}</span>}
			<Title
				id={stub.id}
				className="peek-title"
				value={stub.name}
				onCommit={(name) => handlers.onEdit("name", name, { name })}
			/>
			<div className="peek-tabs" role="tablist" aria-label={`${stub.id} panel`}>
				<button
					type="button"
					role="tab"
					aria-selected={tab === "details"}
					className={tab === "details" ? "chip-toggle on" : "chip-toggle"}
					onClick={() => setTab("details")}
				>
					Details
				</button>
				<button
					type="button"
					role="tab"
					aria-selected={tab === "history"}
					className={tab === "history" ? "chip-toggle on" : "chip-toggle"}
					onClick={() => setTab("history")}
				>
					History
				</button>
			</div>
			{tab === "history" ? (
				<Activity id={stub.id} revision={stub.updated} onRestored={onSaved} />
			) : (
				<PeekDetails stub={stub} kind={kind} cards={cards} lists={lists} handlers={handlers} onSaved={onSaved} />
			)}
		</aside>
	);
}

function PeekDetails({
	stub,
	kind,
	cards,
	lists,
	handlers,
	onSaved,
}: {
	stub: Stub;
	kind: Kind;
	cards: Child[];
	lists: Lists;
	handlers: Handlers;
	onSaved: (record: Stub, undo?: Span, label?: string) => void;
}) {
	return (
		<>
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
			{kind === "epic" && <EstimateFacts estimates={estimatesOf(cards)} />}
			{kind === "epic" && (
				<section className="timeline">
					<h3>
						Tickets <span className="count">{cards.length}</span>
					</h3>
					<p className="epic-progress">
						<ProgressMeter progress={progressOf(cards)} wide />
					</p>
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
			<Stages record={stub} />
			<Content id={stub.id} revision={stub.updated} onSaved={onSaved} />
		</>
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
			<select aria-label="Move the selected tickets" defaultValue="-" onChange={pick(edits.move)}>
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
						aria-label="Set the epic of the selected tickets"
						defaultValue="-"
						onChange={pick((epic) => edits.edit("epic", epic, { epic: epic || null }))}
					>
						<option value="-" disabled>
							Epic…
						</option>
						{lists.epics.map((epic) => (
							<option key={epic.id} value={epic.id}>
								{epic.name}
							</option>
						))}
					</select>
					<select
						aria-label="Set the type of the selected tickets"
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
						aria-label="Set the sprint of the selected tickets"
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
					<select
						aria-label="Set the timebox of the selected tickets"
						defaultValue="-"
						onChange={pick((minutes) =>
							edits.edit("timebox_mins", minutes, { timebox_mins: minutes ? Number(minutes) : null }),
						)}
					>
						<option value="-" disabled>
							Timebox…
						</option>
						<option value="">No timebox</option>
						{TIMEBOXES.map((minutes) => (
							<option key={minutes} value={minutes}>
								{timeboxText(minutes)}
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
	views = [],
}: {
	views?: SavedView[];
	initial: Stub[];
	kind?: Kind;
	lists: Lists;
	children?: Record<string, Child[]>;
}) {
	const epics = lists.epics;
	const router = useRouter();
	const [stubs, setStubs] = useState(initial);
	const [view, setView] = useState<View>(defaultView(kind));
	const [loaded, setLoaded] = useState(false);
	const [dragging, setDragging] = useState<Stub | null>(null);
	const [pending, setPending] = useState<Set<string>>(new Set());
	const [notice, setNotice] = useState<Notice>(null);
	const [openId, setOpenId] = useState<string | null>(null);
	const shownId = useRef(openId);
	shownId.current = openId;
	const [filtersOpen, setFiltersOpen] = useState(false);
	const [toast, setToast] = useState<Undoable | null>(null);
	const [finishing, setFinishing] = useState<Finishing | null>(null);
	const [finishBusy, setFinishBusy] = useState(false);
	const [finishingMany, setFinishingMany] = useState<{ ids: string[]; open: Finishing[] } | null>(null);
	const [undoing, setUndoing] = useState(false);
	const [lastParent, setLastParent] = useState<string | null>(null);
	const [composing, setComposing] = useState(false);
	const [focusedId, setFocusedId] = useState<string | null>(null);
	const [helpOpen, setHelpOpen] = useState(false);
	const [palette, setPalette] = useState<Page | null>(null);
	const [selected, setSelected] = useState<Set<string>>(new Set());
	const [saved, setSaved] = useState(views);
	const [savingView, startSavingView] = useTransition();
	const [viewAsk, setViewAsk] = useState<ViewDialogAsk | null>(null);
	const [inContent, setInContent] = useState<{ query: string; ids: Set<string> } | null>(null);
	const [, startTransition] = useTransition();
	const search = useRef<HTMLInputElement>(null);
	const dndId = useId();

	useEffect(() => setStubs(initial), [initial]);

	useEffect(() => setSaved(views), [views]);

	useEffect(() => setLastParent(loadLastParent(kind)), [kind]);

	useEffect(() => {
		const saved = loadView(kind);
		const params = new URLSearchParams(window.location.search);
		const epic = params.get("epic");
		const failure = params.get("error");
		if (failure) setNotice({ id: "", text: failure });
		if (saved || epic) setView({ ...(saved ?? defaultView(kind)), ...(epic ? { epics: { include: [epic], exclude: [] } } : {}) });
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
		url.searchParams.delete("error");
		url.searchParams.delete("view");
		if (url.href !== window.location.href) window.history.replaceState(null, "", url);
	}, [openId, loaded]);

	const sensors = useSensors(
		useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
		useSensor(TouchSensor, { activationConstraint: { delay: 220, tolerance: 6 } }),
		useSensor(KeyboardSensor),
	);

	const names = useMemo(() => Object.fromEntries(epics.map((epic) => [epic.id, epic.name])), [epics]);
	const query = view.query.trim();
	const epicProjects = useMemo(() => Object.fromEntries(epics.map((epic) => [epic.id, epic.project])), [epics]);
	const found = useMemo<Found>(
		() => ({ names, epicProjects, inContent: inContent?.query === query ? inContent.ids : undefined }),
		[names, epicProjects, inContent, query],
	);
	const projectOptions = useMemo<SearchOption[]>(
		() =>
			lists.projects.map((project) => ({
				value: project.id,
				id: project.id,
				label: project.name,
				done: project.status === "Done",
			})),
		[lists.projects],
	);
	const epicOptions = useMemo<SearchOption[]>(
		() =>
			epics
				.filter((epic) => choicePasses(view.projects, epic.project ?? ""))
				.map((epic) => ({ value: epic.id, id: epic.id, label: epic.name, done: epic.status === "Epic Done" })),
		[epics, view.projects],
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
		const nameOf = mentionNames([...lists.cards, ...lists.epics, ...stubs], lists.aliases);
		return {
			nameOf,
			onOpen: (mentioned) => {
				const id = lists.aliases?.[mentioned] ?? mentioned;
				if (kindOf(id) !== kind) return false;
				const number = id.split("-").at(-1);
				const found =
					stubs.find((stub) => stub.id === id) ??
					stubs.find((stub) => kindOf(stub.id) === kind && stub.id.split("-").at(-1) === number);
				if (!found) return false;
				if (show(found.id)) setFocusedId(found.id);
				return true;
			},
		};
	}, [lists.cards, lists.epics, lists.aliases, stubs, kind]);

	const labels = useMemo(
		() => [...new Set([...stubs.flatMap((stub) => stub.labels ?? []), ...view.labels])].sort(),
		[stubs, view.labels],
	);
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
	const progresses = useMemo(
		() =>
			kind === "epic" ? Object.fromEntries(stubs.map((stub) => [stub.id, progressOf(children[stub.id] ?? [])])) : {},
		[kind, stubs, children],
	);
	const estimates = useMemo(
		() =>
			kind === "epic" ? Object.fromEntries(stubs.map((stub) => [stub.id, estimatesOf(children[stub.id] ?? [])])) : {},
		[kind, stubs, children],
	);
	const tableContext = useMemo(() => contextOf(kind, lists, progresses), [kind, lists, progresses]);
	const tableSort = parseTableSort(view.tableSort);
	const tableRecords = useMemo(
		() => (view.layout === "table" ? visible.filter((stub) => columns.includes(stub.status)) : []),
		[view.layout, visible, columns],
	);
	const fields = useMemo(() => tableColumns(kind, tableRecords), [kind, tableRecords]);
	const rows = useMemo(
		() => sortTable(tableRecords, fields, tableContext, parseTableSort(view.tableSort)),
		[tableRecords, fields, tableContext, view.tableSort],
	);
	const headerSort = view.layout === "table" ? fields.find((column) => column.key === tableSort?.key) : undefined;
	const groupBy = groupingOf(kind, view.groupBy);
	const groupContext = useMemo<GroupContext>(() => {
		const named = (records: Named[]) => Object.fromEntries(records.map((record) => [record.id, record.name]));
		const sprints = [...lists.sprints].sort((a, b) => (a.start ?? "").localeCompare(b.start ?? ""));
		return {
			names: { epic: named(lists.epics), project: named(lists.projects), sprint: named(lists.sprints) },
			order: {
				epic: lists.epics.map((epic) => epic.id),
				project: lists.projects.map((project) => project.id),
				sprint: sprints.map((sprint) => sprint.id),
			},
			epicProjects,
		};
	}, [lists, epicProjects]);
	const swimlanes = useMemo(
		() => (view.layout === "board" ? swimlanesOf(visible, kind, groupBy, groupContext) : null),
		[view.layout, visible, kind, groupBy, groupContext],
	);
	const laneOf = useMemo(
		() => new Map((swimlanes ?? []).flatMap((lane) => lane.stubs.map((stub) => [stub.id, lane] as const))),
		[swimlanes],
	);
	const order = useMemo(() => {
		if (view.layout === "table") return rows;
		const open = columns.filter((column) => !collapsedIn(view).includes(column));
		if (swimlanes)
			return swimlanes
				.filter((lane) => !collapsedIn(view).includes(swimKey(lane)))
				.flatMap((lane) => open.flatMap((column) => lane.stubs.filter((stub) => stub.status === column)));
		return open.flatMap((column) => visible.filter((stub) => stub.status === column));
	}, [columns, visible, view.collapsed, view.listCollapsed, view.layout, rows, swimlanes]);

	useEffect(() => {
		if (!focusedId) return;
		const target = document.querySelector(`[data-card="${CSS.escape(focusedId)}"]`);
		(target?.closest("tbody tr") ?? target)?.scrollIntoView({ block: "nearest", inline: "nearest" });
	}, [focusedId]);

	function show(id: string | null) {
		if (id !== shownId.current && !confirmDiscard()) return false;
		setOpenId(id);
		return true;
	}

	function go(href: string) {
		if (confirmDiscard()) router.push(href);
	}

	function openCard(id: string | null) {
		if (!show(id)) return;
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

	function runBulk(
		ids: string[],
		change: Bulk,
		optimistic: Partial<Stub> | null,
		label: string,
		request = () => bulkChange(ids, change),
	) {
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
			const result = await request();
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
							: label.replace("{n}", `${count} ${kindName(kind)}s`),
						result.undo,
					),
				);
			router.refresh();
		});
	}

	function bulkEdits(ids: string[]): Edits {
		return {
			label: ids.length === 1 ? ids[0] : `${ids.length} ${kindName(kind)}s`,
			move: (column) => {
				if (kind === "epic" && column === "Epic Done") {
					const open = ids.flatMap((id) => {
						const stub = stubs.find((other) => other.id === id);
						const cards = stub && stub.status !== column ? openTickets(children[id] ?? []) : [];
						return stub && cards.length > 0 ? [{ id, name: stub.name, open: cards }] : [];
					});
					if (open.length > 0) return setFinishingMany({ ids, open });
				}
				runBulk(ids, { op: "move", column }, movedTo(column), `Moved {n} to ${column}`);
			},
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
		if (openId && !show(id)) return;
		setFocusedId(id);
	}

	function stepColumn(by: number) {
		const current = order.find((stub) => stub.id === (focusedId ?? openId));
		const shown = columns.filter((column) => order.some((stub) => stub.status === column));
		if (shown.length === 0) return;
		const from = current ? shown.indexOf(current.status) : -1;
		const column = shown[Math.min(shown.length - 1, Math.max(0, from < 0 ? 0 : from + by))];
		const id = order.find((stub) => stub.status === column)?.id;
		if (!id) return;
		if (openId && !show(id)) return;
		setFocusedId(id);
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
		return {
			label: stub.id,
			move: handlers.onMove,
			edit: handlers.onEdit,
			archive: bulkEdits(ids).archive,
			duplicate: () => duplicate(stub.id),
		};
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
				label: "Select it, to change several tickets at once",
				hint: "X",
				run: () => toggleSelected(record.id),
			});
		}
		if (record && chosen.length === 0) {
			actions.push(
				{ id: "do:copy", group: record.id, label: "Copy id", hint: "Cmd/Ctrl+.", run: () => copy(record.id, false) },
				{ id: "do:link", group: record.id, label: "Copy link", run: () => copy(record.id, true) },
				{ id: "do:page", group: record.id, label: "Open its page", run: () => go(`/card/${record.id}`) },
			);
		}
		const general: Command[] = [
			...LAYOUTS.filter(([layout]) => layout !== view.layout).map(([layout, label]) => ({
				id: `go:layout:${layout}`,
				group: "Board",
				label: `Show as a ${label.toLowerCase()}`,
				keywords: layout === "table" ? "every field property columns" : undefined,
				run: () => update({ layout }),
			})),
			...saved.map((other) => ({
				id: `go:saved:${other.name}`,
				group: "Board",
				label: `Show the saved view ${other.name}`,
				keywords: "view saved recall",
				run: () => recallView(other.name),
			})),
			{
				id: "go:save-view",
				group: "Board",
				label: "Save this view as…",
				keywords: "view name",
				run: () => setViewAsk({ mode: "save", name: currentView ?? "" }),
			},
			{
				id: "go:other",
				group: "Board",
				label: kind === "card" ? "Go to epics" : "Go to tickets",
				run: () => go(kind === "card" ? "/epics" : "/"),
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
		update({ query: "", types: [], projects: NO_CHOICE, epics: NO_CHOICE, labels: [], urgent: false, blocked: false, claimed: false, overrunning: false });
	}

	useKeys((event) => {
		if (helpOpen || palette || viewAsk || event.defaultPrevented) return;
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
			else if (openId) show(null);
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
				show(focusedId);
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
		}
	});

	const shortcuts: Shortcut[] = [
		{ keys: ["j", "k"], label: "Next or previous ticket" },
		{ keys: ["h", "l"], label: "Previous or next column" },
		{ keys: ["Enter"], label: "Open the focused ticket" },
		{ keys: ["Esc"], label: "Close the ticket, or clear the focus" },
		{ keys: ["Cmd/Ctrl", "K"], label: "Command menu: jump to a ticket or run an action" },
		{ keys: ["x"], label: "Select the focused ticket, or Shift-click one" },
		{ keys: ["s"], label: "Move the ticket, or the selected tickets, to a column" },
		...(kind === "card" ? [{ keys: ["e"], label: "Set the epic of the card, or the selected tickets" }] : []),
		{ keys: ["/"], label: "Search" },
		{ keys: ["Cmd/Ctrl", "."], label: "Copy the ticket's id" },
		{ keys: ["Cmd/Ctrl", "Shift", "."], label: "Copy a link to the ticket" },
		{ keys: ["Cmd/Ctrl", "Z"], label: "Undo the last change" },
		{ keys: ["?"], label: "Show these shortcuts" },
	];

	function update(change: Partial<View>) {
		setView((current) => ({ ...current, ...change }));
	}

	function viewToSave(): Record<string, unknown> {
		const { collapsed, listCollapsed, ...rest } = view;
		return rest;
	}

	function recallView(name: string) {
		const chosen = saved.find((other) => other.name === name);
		if (!chosen) return;
		setView(
			restoredView(kind, { ...(chosen.view as Partial<View>), collapsed: view.collapsed, listCollapsed: view.listCollapsed }),
		);
		setToast(toastOf(`Showing the saved view ${name}`));
	}

	function saveCurrentView(typed: string) {
		setViewAsk(null);
		startSavingView(async () => {
			const result = await storeView(kind, typed, viewToSave());
			if (result.error) setNotice({ id: "", text: `Could not save the view: ${result.error}` });
			if (result.views) {
				setSaved(result.views);
				setToast(toastOf(`Saved the view ${typed}`));
			}
		});
	}

	function deleteView(name: string) {
		setViewAsk(null);
		startSavingView(async () => {
			const result = await forgetView(kind, name);
			if (result.error) setNotice({ id: "", text: `Could not delete the view: ${result.error}` });
			if (result.views) {
				setSaved(result.views);
				setToast(toastOf(`Deleted the view ${name}`));
			}
		});
	}

	function toggleType(type: string) {
		update({ types: view.types.includes(type) ? view.types.filter((t) => t !== type) : [...view.types, type] });
	}

	function toggleLabel(label: string) {
		update({ labels: view.labels.includes(label) ? view.labels.filter((l) => l !== label) : [...view.labels, label] });
	}

	function toggleColumn(column: string) {
		update(toggledIn(view, column));
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
		request: () => Promise<{
			record?: Stub;
			error?: string;
			moved?: string;
			archived?: boolean;
			undo?: Span;
			more?: Change[];
		}>,
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
				if (moved) setOpenId((opened) => (opened === id ? moved : opened));
				if (moved || result.archived) router.refresh();
				return;
			}
			const fresh = result.record;
			if (fresh) {
				setStubs((current) => current.map((s) => (s.id === id ? fresh : s)));
				if (fresh.id !== id) setOpenId((opened) => (opened === id ? fresh.id : opened));
				setToast(undoable(fresh.id, result.undo, withNewId(label, id, fresh.id), result.more));
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

	function move(id: string, column: string, rank?: number, checked = false, sets: FieldChange[] = []) {
		const stub = stubs.find((s) => s.id === id);
		if (!stub || (stub.status === column && rank === undefined && sets.length === 0)) return;
		if (!checked && kind === "epic" && column === "Epic Done" && stub.status !== column) {
			const open = openTickets(children[id] ?? []);
			if (open.length > 0) {
				setFinishing({ id, name: stub.name, open, rank });
				return;
			}
		}
		const moved = stub.status === column ? `Reordered ${id} in ${column}` : `Moved ${id} to ${column}`;
		const label =
			sets.length > 0 ? `${moved} and changed its ${sets.map((set) => fieldName(set.field)).join(" and ")}` : moved;
		const changed = Object.assign({}, ...sets.map((set) => set.change)) as Partial<Stub>;
		const fields: FieldSet[] = sets.map(({ field, value }) => ({ field, value }));
		apply(
			id,
			{ ...(stub.status === column ? {} : movedTo(column)), ...(rank === undefined ? {} : { rank }), ...changed },
			() => dropCard(id, column, rank, fields),
			label,
		);
	}

	function finish(chosen: Finishing) {
		setFinishBusy(true);
		setNotice(null);
		setToast(null);
		startTransition(async () => {
			const result = await finishEpic(
				chosen.id,
				chosen.open.map((card) => card.id),
			);
			setFinishBusy(false);
			setFinishing(null);
			const fresh = result.record;
			if (fresh) setStubs((current) => current.map((s) => (s.id === chosen.id ? fresh : s)));
			if (result.errors.length > 0) setNotice({ id: "", text: result.errors.join("; ") });
			if (result.undo.length > 0)
				setToast(
					toastOf(
						`Deprioritised ${chosen.open.length === 1 ? "1 open ticket" : `${chosen.open.length} open tickets`} of ${chosen.id}${fresh ? " and moved it to Epic Done" : ""}`,
						result.undo,
					),
				);
			router.refresh();
		});
	}

	function finishMany(chosen: { ids: string[]; open: Finishing[] }) {
		setFinishingMany(null);
		const cards = chosen.open.flatMap((epic) => epic.open.map((card) => card.id));
		const tickets = cards.length === 1 ? "1 open ticket" : `${cards.length} open tickets`;
		runBulk(
			chosen.ids,
			{ op: "move", column: "Epic Done" },
			movedTo("Epic Done"),
			`Deprioritised ${tickets} and moved {n} to Epic Done`,
			() => finishEpics(chosen.ids, cards),
		);
	}

	function placement(id: string, overId: string): { column: string; rank?: number; swimlane?: Swimlane } | null {
		if (!overId.startsWith("card:")) {
			const swim = overId.match(/^swim:(\d+):(.*)$/);
			const swimlane = swim ? swimlanes?.[Number(swim[1])] : undefined;
			const column = swim ? swim[2] : overId;
			if (view.sort !== "manual") return { column, swimlane };
			const lane = (swimlane?.stubs ?? visible).filter((stub) => stub.status === column && stub.id !== id);
			const last = lane.at(-1);
			return { column, rank: last ? effectiveRank(last) + 1 : undefined, swimlane };
		}
		const target = stubs.find((stub) => stub.id === overId.slice(5));
		if (!target || target.id === id) return null;
		const swimlane = laneOf.get(target.id);
		if (view.sort !== "manual") return { column: target.status, swimlane };
		const lane = (swimlane?.stubs ?? visible).filter((stub) => stub.status === target.status && stub.id !== id);
		const index = lane.findIndex((stub) => stub.id === target.id);
		const before = index > 0 ? effectiveRank(lane[index - 1]) : effectiveRank(target) - 1;
		return { column: target.status, rank: (before + effectiveRank(target)) / 2, swimlane };
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
			onOpen: show,
		};
	}

	async function compose(draft: Draft): Promise<string | null> {
		setNotice(null);
		const ranks = stubs.filter((stub) => stub.status === draft.status).map(effectiveRank);
		const { name, status, ...options } = draft;
		const parent = kind === "epic" ? options.project : options.epic;
		if (parent) {
			setLastParent(parent);
			saveLastParent(kind, parent);
		}
		const result = await createCard(kind, name, status, {
			...options,
			rank: kind === "card" && ranks.length > 0 ? Math.max(...ranks) + 1 : undefined,
		});
		const fresh = result.record;
		if (!fresh) {
			if (!result.moved) return `Could not create the ${kindName(kind)}: ${result.error ?? "board-card made nothing"}`;
			setComposing(false);
			setNotice({ id: "", text: result.error ?? "" });
			router.refresh();
			return null;
		}
		setStubs((current) => [...current, fresh]);
		setComposing(false);
		if (collapsedIn(view).includes(fresh.status)) toggleColumn(fresh.status);
		openCard(fresh.id);
		setToast(toastOf(`Created ${fresh.id}`));
		router.refresh();
		return null;
	}

	function newDock(placement: string, collapsed = false) {
		const parents =
			kind === "epic"
				? lists.projects.filter((project) => project.status !== "Done")
				: lists.epics.filter((epic) => epic.status !== "Epic Done");
		const parent = parents.find((option) => option.id === lastParent)?.id ?? parents[0]?.id;
		return (
			<div className={`new-dock ${placement}`}>
				<NewRecord
					kind={kind}
					lists={lists}
					open={composing}
					label={collapsed ? "+" : undefined}
					defaults={{
						status: boardColumns(kind)[0],
						type: kind === "card" && view.types.length === 1 ? view.types[0] : undefined,
						epic: kind === "card" ? (onlyEpic(view) ?? parent) : undefined,
						project: kind === "epic" ? parent : undefined,
					}}
					onOpenChange={setComposing}
					onCreate={compose}
				/>
			</div>
		);
	}

	function duplicate(id: string) {
		setNotice(null);
		startTransition(async () => {
			const result = await duplicateCard(id);
			const fresh = result.record;
			if (!fresh) {
				setNotice({ id: result.moved ?? id, text: `${id}: ${result.error ?? "board-card made nothing"}` });
				return;
			}
			setStubs((current) => [...current, fresh]);
			openCard(fresh.id);
			setToast(toastOf(`Duplicated ${id} as ${fresh.id}`));
			router.refresh();
		});
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
		if (!place) return;
		const stub = stubs.find((s) => s.id === id);
		if (!place.swimlane || !stub) {
			move(id, place.column, place.rank);
			return;
		}
		const sets = droppedInto(stub, laneOf.get(id), place.swimlane, groupBy, kind, groupContext);
		if (typeof sets === "string") {
			setNotice({ id: "", text: sets });
			return;
		}
		move(id, place.column, place.rank, false, sets);
	}

	const projectIds = new Set(lists.projects.map((project) => project.id));
	const homeless = stubs.filter((stub) =>
		kind === "epic" ? !stub.project || !projectIds.has(stub.project) : !stub.epic || !names[stub.epic],
	);
	const count = filterCount(view);
	const currentView = saved.find(
		(other) => JSON.stringify(restoredView(kind, other.view as Partial<View>)) === JSON.stringify(restoredView(kind, viewToSave() as Partial<View>)),
	)?.name;
	const backlog = boardColumns(kind)[0];
	const dockColumn = columns.includes(backlog) ? backlog : view.layout === "list" ? null : columns[0];
	const groupProps = (column: string, swimlane?: Swimlane, index = 0) => ({
		column,
		dropId: swimlane ? `swim:${index}:${column}` : undefined,
		stubs: (swimlane?.stubs ?? visible).filter((stub) => stub.status === column),
		total: (swimlane?.stubs ?? stubs).filter((stub) => stub.status === column).length,
		collapsed: collapsedIn(view).includes(column),
		onToggle: () => toggleColumn(column),
		pending,
		focusedId,
		selected,
		onOpen: clickCard,
		dock:
			!swimlane && column === dockColumn
				? view.layout === "list"
					? newDock("list-dock")
					: newDock("lane-dock", collapsedIn(view).includes(column))
				: undefined,
	});

	return (
		<Names.Provider value={names}>
			<Rollups progresses={progresses} estimates={estimates}>
				<MentionContext.Provider value={mentions}>
					<div className={`board${open ? " peeking" : ""}`}>
						<div className="toolbar">
							<select
								className="view-pick saved-views"
								value=""
								disabled={savingView}
								onChange={(event) => {
									const [action, name] = event.target.value.split(/:(.*)/s);
									event.target.value = "";
									if (action === "recall") recallView(name);
									else if (action === "save") setViewAsk({ mode: "save", name: currentView ?? "" });
									else if (action === "delete") setViewAsk({ mode: "delete", name });
								}}
								aria-label="Saved views"
								title="Name the filters, grouping, sort and layout, kept on the board, and bring them back"
							>
								<option value="" disabled>
									{currentView ? `View: ${currentView}` : "Saved views"}
								</option>
								{saved.length > 0 && (
									<optgroup label="Show">
										{saved.map((other) => (
											<option key={other.name} value={`recall:${other.name}`}>
												{other.name}
											</option>
										))}
									</optgroup>
								)}
								<option value="save:">{currentView ? `Save as… (now ${currentView})` : "Save this view as…"}</option>
								{saved.length > 0 && (
									<optgroup label="Delete">
										{saved.map((other) => (
											<option key={other.name} value={`delete:${other.name}`}>
												Delete {other.name}
											</option>
										))}
									</optgroup>
								)}
							</select>
							<select
								className="view-pick"
								value={groupBy}
								onChange={(event) => update({ groupBy: groupingOf(kind, event.target.value) })}
								aria-label="Group by"
								title="Swimlanes on the board layout - dropping a ticket into one sets that field"
							>
								{GROUPINGS[kind].map(([key, label]) => (
									<option key={key} value={key}>
										{label}
									</option>
								))}
							</select>
							<div className="segmented" role="group" aria-label="Layout">
								{LAYOUTS.map(([layout, label]) => (
									<button
										key={layout}
										type="button"
										className={view.layout === layout ? "on" : undefined}
										aria-pressed={view.layout === layout}
										onClick={() => update({ layout })}
									>
										{label}
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
								<ChoiceSelect
									label="Project"
									all="All projects"
									value={view.projects}
									options={projectOptions}
									onChange={(projects) => {
										const fits = (epic: string) =>
											!epics.some((other) => other.id === epic) || choicePasses(projects, epicProjects[epic] ?? "");
										update({ projects, epics: keptIn(view.epics, fits) });
									}}
								/>
								{kind === "card" && (
									<ChoiceSelect
										label="Epic"
										all="All epics"
										value={view.epics}
										options={epicOptions}
										onChange={(epics) => update({ epics })}
									/>
								)}
								{labels.length > 0 && (
									<div className="chips" role="group" aria-label="Label">
										{labels.map((label) => (
											<button
												key={label}
												type="button"
												className={`chip-toggle label${view.labels.includes(label) ? " on" : ""}`}
												aria-pressed={view.labels.includes(label)}
												title={`Only the ${kindName(kind)}s labelled ${label}`}
												onClick={() => toggleLabel(label)}
											>
												{label}
											</button>
										))}
									</div>
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
								value={headerSort ? HEADER_SORT : view.sort}
								onChange={(event) =>
									update({ sort: event.target.value as Sort, ...(headerSort ? { tableSort: "" } : {}) })
								}
								aria-label="Sort"
								title={headerSort ? "The table is sorted by a column header - pick a sort here to clear it" : undefined}
							>
								{headerSort && (
									<option value={HEADER_SORT} disabled>
										By {headerSort.label}
									</option>
								)}
								<option value="manual">Manual</option>
								<option value="newest">Newest</option>
								<option value="oldest">Oldest</option>
								{kind === "card" && <option value="complexity">Complexity</option>}
								<option value="moved">Last moved</option>
								{kind === "card" && <option value="days">Longest in column</option>}
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

						{homeless.length > 0 && (
							<p className="board-homeless">
								{kind === "epic"
									? homeless.length === 1
										? "This epic needs a project"
										: "These epics need a project"
									: homeless.length === 1
										? "This ticket needs an epic"
										: "These tickets need an epic"}
								, which only a person can give {homeless.length === 1 ? "it" : "them"}:{" "}
								{homeless.map((stub, index) => (
									<span key={stub.id}>
										{index > 0 && ", "}
										<button type="button" className="ident-link" onClick={() => openCard(stub.id)}>
											{stub.id} {stub.name}
										</button>
									</span>
								))}
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
								{view.layout === "board" && swimlanes ? (
									<div className="swimlanes">
										{swimlanes.map((swimlane, index) => {
											const folded = collapsedIn(view).includes(swimKey(swimlane));
											return (
												<section key={swimlane.key} className={`swimlane${swimlane.urgent ? " urgent" : ""}`}>
													<button
														type="button"
														className="swimlane-head"
														aria-expanded={!folded}
														onClick={() => toggleColumn(swimKey(swimlane))}
													>
														<span className="caret">{folded ? "▸" : "▾"}</span>
														<span className="lane-name">{swimlane.label}</span>
														<span className="count">{swimlane.stubs.length}</span>
														<Points stubs={swimlane.stubs} />
													</button>
													{!folded && (
														<div className="lanes">
															{columns.map((column) => (
																<Lane key={column} {...groupProps(column, swimlane, index)} />
															))}
														</div>
													)}
												</section>
											);
										})}
										{newDock("swim-dock")}
									</div>
								) : view.layout === "board" ? (
									<div className="lanes">
										{columns.map((column) => (
											<Lane key={column} {...groupProps(column)} />
										))}
									</div>
								) : view.layout === "table" ? (
									<Table
										kind={kind}
										records={rows}
										columns={fields}
										context={tableContext}
										sort={tableSort}
										onSort={(key) => update({ tableSort: nextTableSort(tableSort, key) })}
										pending={pending}
										focusedId={focusedId}
										selected={selected}
										onOpen={clickCard}
										footer={newDock("table-dock")}
									/>
								) : (
									<div className="list">
										{columns.map((column) => (
											<ListGroup key={column} {...groupProps(column)} />
										))}
										{!dockColumn && newDock("list-dock")}
									</div>
								)}
								<DragOverlay dropAnimation={null}>
									{dragging && (
										<div className="card drag-overlay">
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
										onClose={() => show(null)}
										onCopy={() => copy(open.id, true)}
										onDuplicate={() => duplicate(open.id)}
										onArchive={() => bulkEdits([open.id]).archive?.()}
										onSaved={(saved, span, label) => {
											const was = open.id;
											setStubs((current) => current.map((s) => (s.id === saved.id || s.id === was ? saved : s)));
											if (saved.id !== was) setOpenId((opened) => (opened === was ? saved.id : opened));
											setToast(undoable(saved.id, span, label ?? `Changed the content of ${saved.id}`));
											router.refresh();
										}}
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
						{finishing && (
							<EpicDoneDialog
								finishing={finishing}
								busy={finishBusy}
								onDeprioritise={() => finish(finishing)}
								onAnyway={() => {
									setFinishing(null);
									move(finishing.id, "Epic Done", finishing.rank, true);
								}}
								onCancel={() => setFinishing(null)}
							/>
						)}
						{finishingMany && (
							<EpicsDoneDialog
								finishing={finishingMany.open}
								total={finishingMany.ids.length}
								onDeprioritise={() => finishMany(finishingMany)}
								onAnyway={() => {
									setFinishingMany(null);
									runBulk(finishingMany.ids, { op: "move", column: "Epic Done" }, movedTo("Epic Done"), "Moved {n} to Epic Done");
								}}
								onCancel={() => setFinishingMany(null)}
							/>
						)}
						{viewAsk && (
							<ViewDialog
								ask={viewAsk}
								existing={saved.map((other) => other.name)}
								onSave={saveCurrentView}
								onDelete={deleteView}
								onCancel={() => setViewAsk(null)}
							/>
						)}
						{helpOpen && <ShortcutHelp shortcuts={shortcuts} onClose={() => setHelpOpen(false)} />}
						{palette && <Palette start={palette} onClose={() => setPalette(null)} />}
					</div>
				</MentionContext.Provider>
			</Rollups>
		</Names.Provider>
	);
}
