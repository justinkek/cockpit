"use client";

import {
	DndContext,
	type DragEndEvent,
	DragOverlay,
	type DragStartEvent,
	PointerSensor,
	TouchSensor,
	useDraggable,
	useDroppable,
	useSensor,
	useSensors,
} from "@dnd-kit/core";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
	type CSSProperties,
	type PointerEvent as ReactPointerEvent,
	type ReactNode,
	useEffect,
	useId,
	useMemo,
	useRef,
	useState,
	useTransition,
} from "react";
import {
	type Change,
	createMilestone,
	dropBreak,
	dropCard,
	editCard,
	finishEpic,
	loadComments,
	postComment,
	type Ranked,
	rankPlan,
	removeMilestone,
	resolveThread,
	saveBreak,
	setBoardTracks,
	type Span,
	undoChange,
} from "@/app/actions";
import { Content, confirmDiscard } from "@/app/content";
import { Fields, type Handlers, type Lists, TextField, Title, useHydrated } from "@/app/fields";
import { EpicDoneDialog, type Finishing, openTickets } from "@/app/epic-done";
import { EstimateFacts, estimatesTitle } from "@/app/estimates";
import { ProgressMeter } from "@/app/progress";
import { Stages } from "@/app/stages";
import { toastOf, typingIn, type Undoable, UndoToast, undoable } from "@/app/toast";
import { progressOf } from "@/lib/metrics";
import {
	AVERAGE_SPEED_DAYS,
	blockedSpansOf,
	CONFIDENCES,
	dayOf,
	dayText,
	daysOff,
	estimatesOf,
	lateText,
	mondayOf,
	openWorkOf,
	planOf,
	planOrder,
	pointsOf,
	type Refinement,
	refinementOf,
	type Row,
	spanOf,
	type AverageSpeed,
	type Team,
	type TrackSpeed,
	trackSpeedsOf,
} from "@/lib/plan";
import { type Break, type Card, type CommentThread, fieldName, kindOf, movedTo, phaseOf } from "@/lib/shared";

const DAY = 86400000;
const SCALES = { weeks: 8, months: 2.4 } as const;
type Scale = keyof typeof SCALES;
const PREFERENCES = "cockpit-plan";
const DONE = "Done";
const HOLD = 280;

type Project = {
	id: string;
	name: string;
	icon?: string | null;
	priority?: number | null;
	tracks?: number | null;
	status?: string | null;
};
type Prefs = { scale: Scale; grouped: boolean };
type Mode = "target" | "draw" | "milestone";
type Drag = {
	mode: Mode;
	id: string;
	start: number | null;
	target: number | null;
	anchor: number | null;
	delta: number;
	moved: boolean;
};
type Notice = { id: string; text: string } | null;
type Editing = { id: string | null; name: string; date: string } | null;
type Outcome = { record?: Card; error?: string; moved?: string; archived?: boolean; undo?: Span; more?: Change[] };

function loadPrefs(): Prefs {
	try {
		const saved = JSON.parse(window.localStorage.getItem(PREFERENCES) ?? "{}");
		return { scale: saved.scale === "months" ? "months" : "weeks", grouped: saved.grouped !== false };
	} catch {
		return { scale: "weeks", grouped: true };
	}
}

function savePrefs(prefs: Prefs) {
	try {
		window.localStorage.setItem(PREFERENCES, JSON.stringify(prefs));
	} catch {}
}

function short(day: number) {
	const date = new Date(day * DAY);
	return date.toLocaleDateString(undefined, {
		day: "numeric",
		month: "short",
		timeZone: "UTC",
		...(date.getUTCFullYear() === new Date().getFullYear() ? {} : { year: "numeric" }),
	});
}

function long(day: number) {
	return new Date(day * DAY).toLocaleDateString(undefined, {
		weekday: "short",
		day: "numeric",
		month: "short",
		year: "numeric",
		timeZone: "UTC",
	});
}

function figure(points: number) {
	return points >= 10 ? Math.round(points).toString() : (Math.round(points * 10) / 10).toString();
}

function moved(drag: Drag): { start: number | null; target: number | null } {
	const from = drag.mode === "draw" ? drag.anchor : drag.target;
	if (from == null) return { start: drag.start, target: drag.target };
	return { start: drag.start, target: Math.max(from + drag.delta, drag.start ?? Number.NEGATIVE_INFINITY) };
}

type IconName =
	| "none"
	| "good"
	| "plan"
	| "risk"
	| "done"
	| "projected"
	| "milestone"
	| "target"
	| "late"
	| "blocked";

function Icon({ name }: { name: IconName }) {
	const shapes: Record<IconName, ReactNode> = {
		none: <circle cx="6" cy="6" r="4.5" fill="none" stroke="currentColor" strokeWidth="1.5" strokeDasharray="2 1.6" />,
		good: <circle cx="6" cy="6" r="5" fill="currentColor" />,
		plan: <path d="M6 1 L11.2 10.6 H0.8 Z" fill="currentColor" />,
		risk: (
			<>
				<path d="M3.9 0.8h4.2l3.1 3.1v4.2l-3.1 3.1H3.9L0.8 8.1V3.9z" fill="currentColor" />
				<path d="M6 3v3.6M6 8.2v0.9" stroke="var(--panel)" strokeWidth="1.5" strokeLinecap="round" />
			</>
		),
		done: (
			<path
				d="M1.5 6.4 L4.6 9.4 L10.5 2.8"
				fill="none"
				stroke="currentColor"
				strokeWidth="2"
				strokeLinecap="round"
				strokeLinejoin="round"
			/>
		),
		projected: <path d="M6 1 L11 6 L6 11 L1 6 Z" fill="var(--panel)" stroke="currentColor" strokeWidth="1.6" />,
		milestone: <path d="M6 0.5 L11.5 6 L6 11.5 L0.5 6 Z" fill="currentColor" />,
		target: <path d="M2.5 11V1 M2.5 1.5h7l-2 2.5 2 2.5h-7" fill="none" stroke="currentColor" strokeWidth="1.5" />,
		late: <rect x="0.5" y="3" width="11" height="6" rx="1" className="late-swatch" />,
		blocked: (
			<>
				<circle cx="6" cy="6" r="5.2" fill="currentColor" />
				<path d="M3.2 6h5.6" stroke="var(--panel)" strokeWidth="1.8" strokeLinecap="round" />
			</>
		),
	};
	return (
		<svg className={`plan-icon icon-${name}`} viewBox="0 0 12 12" width="12" height="12" aria-hidden="true">
			{shapes[name]}
		</svg>
	);
}

const STATUSES: Record<string, { label: string; short: string; icon: IconName; tone: string; title: string }> = {
	"": {
		label: "No status",
		short: "No status",
		icon: "none",
		tone: "none",
		title: "Nobody has said how confident they are",
	},
	"On track": { label: "On track", short: "On track", icon: "good", tone: "good", title: "On track for its target" },
	"At risk - plan in place": {
		label: "At risk · plan in place",
		short: "At risk",
		icon: "plan",
		tone: "plan",
		title: "At risk, with a plan in place to bring it back",
	},
	"At risk - no plan": {
		label: "At risk · no plan",
		short: "No plan",
		icon: "risk",
		tone: "risk",
		title: "At risk, with no plan yet to bring it back",
	},
	[DONE]: { label: "Done", short: "Done", icon: "done", tone: "done", title: "Delivered - it is in Epic Done" },
};

function StatusChip({ epic, row, onPick }: { epic: Card; row: Row | undefined; onPick: (value: string) => void }) {
	const done = epic.status === "Epic Done";
	const value = done ? DONE : (epic.confidence ?? "");
	const shown = STATUSES[value] ?? STATUSES[""];
	const late = row?.atRisk ? ` - projected ${lateText(row.late, false)}, so it may no longer be on track` : "";
	return (
		<label
			className={`plan-status tone-${shown.tone}${row?.atRisk ? " suggest" : ""}`}
			title={
				done ? `${shown.title} - move it out of Epic Done on the Epics board to plan it again` : `${shown.title}${late}`
			}
		>
			<Icon name={shown.icon} />
			<span className="plan-status-text">{shown.label}</span>
			<span className="plan-status-short">{shown.short}</span>
			{row?.atRisk && (
				<span className="plan-suggest" aria-label="Projected late - consider At risk">
					<Icon name="plan" />
					Late?
				</span>
			)}
			{!done && (
				<select aria-label={`Status of ${epic.id}`} value={value} onChange={(event) => onPick(event.target.value)}>
					<option value="">No status</option>
					{CONFIDENCES.map((confidence) => (
						<option key={confidence} value={confidence}>
							{STATUSES[confidence].label}
						</option>
					))}
					<option value={DONE}>Done - move it to Epic Done</option>
				</select>
			)}
		</label>
	);
}

function LearningCell({ id, value, onCommit }: { id: string; value: string; onCommit: (value: string) => void }) {
	const [editing, setEditing] = useState(false);
	const [draft, setDraft] = useState(value);
	const cancelled = useRef(false);
	if (!editing) {
		return (
			<button
				type="button"
				className={`plan-learning${value ? "" : " empty"}`}
				title={value || "Add what this epic taught you"}
				onClick={() => {
					setDraft(value);
					setEditing(true);
				}}
			>
				{value || "Add a learning"}
			</button>
		);
	}
	return (
		<textarea
			className="plan-learning-edit"
			aria-label={`Learning of ${id}`}
			value={draft}
			ref={(area) => area?.focus()}
			onChange={(event) => setDraft(event.target.value)}
			onKeyDown={(event) => {
				if (event.key === "Enter" && !event.shiftKey) {
					event.preventDefault();
					event.currentTarget.blur();
				}
				if (event.key === "Escape") {
					event.stopPropagation();
					cancelled.current = true;
					event.currentTarget.blur();
				}
			}}
			onBlur={() => {
				setEditing(false);
				if (cancelled.current) {
					cancelled.current = false;
					return;
				}
				const next = draft.trim();
				if (next !== value) onCommit(next);
			}}
		/>
	);
}

function CommentsCell({ epic, onCount }: { epic: Card; onCount: (id: string) => void }) {
	const [threads, setThreads] = useState<CommentThread[] | null>(null);
	const [open, setOpen] = useState(false);
	const [draft, setDraft] = useState("");
	const [error, setError] = useState("");
	const [busy, startTransition] = useTransition();
	const frame = useRef<HTMLDivElement>(null);
	const count = epic.comments ?? 0;

	useEffect(() => {
		if (count === 0 && !open) {
			setThreads([]);
			return;
		}
		let live = true;
		loadComments(epic.id).then((result) => {
			if (!live) return;
			if (result.threads) setThreads(result.threads.filter((thread) => !thread.resolved));
			else setError(result.error ?? "");
		});
		return () => {
			live = false;
		};
	}, [epic.id, epic.updated, count, open]);

	useEffect(() => {
		if (!open) return;
		function away(event: PointerEvent) {
			if (frame.current && !frame.current.contains(event.target as Node)) setOpen(false);
		}
		document.addEventListener("pointerdown", away);
		return () => document.removeEventListener("pointerdown", away);
	}, [open]);

	const latest = threads?.[threads.length - 1]?.comments.at(-1);

	function send() {
		const text = draft.trim();
		if (!text) return;
		startTransition(async () => {
			const result = await postComment(epic.id, text);
			if (result.error) {
				setError(result.error);
				return;
			}
			setDraft("");
			setError("");
			setThreads((result.threads ?? []).filter((thread) => !thread.resolved));
			onCount(epic.id);
		});
	}

	function resolve(thread: string) {
		startTransition(async () => {
			const result = await resolveThread(epic.id, thread);
			if (result.error) setError(result.error);
			else {
				setThreads((result.threads ?? []).filter((one) => !one.resolved));
				onCount(epic.id);
			}
		});
	}

	return (
		<div className="plan-comments" ref={frame}>
			<button
				type="button"
				className={`plan-comment-open${count > 0 ? " has" : ""}`}
				aria-expanded={open}
				title={count > 0 ? `${count} open comment ${count === 1 ? "thread" : "threads"}` : "Add a comment"}
				onClick={() => setOpen(!open)}
			>
				<svg viewBox="0 0 16 16" aria-hidden="true">
					<path d="M3 3.5h10a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1H8l-3 2.5v-2.5H3a1 1 0 0 1-1-1v-6a1 1 0 0 1 1-1z" />
				</svg>
				{count > 0 ? count : ""}
				<span className="plan-comment-text">
					{latest ? `${latest.author}: ${latest.text}` : count > 0 ? "Loading…" : "Comment"}
				</span>
			</button>
			{open && (
				<div className="plan-popover plan-thread-list" role="dialog" aria-label={`Comments on ${epic.id}`}>
					{(threads ?? []).length === 0 && <p className="empty">No open comment on {epic.id}.</p>}
					{(threads ?? []).map((thread) => (
						<div key={thread.thread} className="plan-thread">
							{thread.anchor && <q>{thread.anchor}</q>}
							{thread.comments.map((comment) => (
								<p key={comment.id}>
									<strong>{comment.author}</strong> {comment.text}
								</p>
							))}
							<button type="button" className="quiet" disabled={busy} onClick={() => resolve(thread.thread)}>
								Resolve
							</button>
						</div>
					))}
					<textarea
						aria-label={`New comment on ${epic.id}`}
						placeholder="Add a comment on the epic…"
						value={draft}
						onChange={(event) => setDraft(event.target.value)}
						onKeyDown={(event) => {
							if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
								event.preventDefault();
								send();
							}
							if (event.key === "Escape") {
								event.stopPropagation();
								setOpen(false);
							}
						}}
					/>
					{error && <p className="notice error">{error}</p>}
					<span className="plan-popover-actions">
						<Link href={`/epics?open=${epic.id}`} className="quiet-link">
							Reply on the epic
						</Link>
						<button type="button" disabled={busy || !draft.trim()} onClick={send}>
							Comment
						</button>
					</span>
				</div>
			)}
		</div>
	);
}

function Handle({ id, name }: { id: string; name: string }) {
	const { attributes, listeners, setNodeRef } = useDraggable({ id: `row:${id}` });
	return (
		<button
			type="button"
			ref={setNodeRef}
			className="plan-grip"
			{...attributes}
			{...listeners}
			aria-label={`Reorder ${name} - drag`}
			title="Drag onto another epic to rank it just above or below that one, and the row moves to where that priority schedules it"
		>
			<svg viewBox="0 0 8 14" aria-hidden="true">
				<circle cx="2" cy="2" r="1.2" />
				<circle cx="6" cy="2" r="1.2" />
				<circle cx="2" cy="7" r="1.2" />
				<circle cx="6" cy="7" r="1.2" />
				<circle cx="2" cy="12" r="1.2" />
				<circle cx="6" cy="12" r="1.2" />
			</svg>
		</button>
	);
}

function RowDrop({ id, children, className }: { id: string; children: ReactNode; className: string }) {
	const { setNodeRef, isOver } = useDroppable({ id: `row:${id}` });
	return (
		<div ref={setNodeRef} className={`${className}${isOver ? " over" : ""}`} data-epic={id}>
			{children}
		</div>
	);
}

function cardPointsTitle(card: Card) {
	if (card.type === "Timebox") return "A timebox carries no estimate";
	if ((card.complexity ?? 0) > 0) return `TR complexity ${card.complexity}`;
	if ((card.estimate ?? 0) > 0) return `TD estimate ${card.estimate}, with no TR complexity yet`;
	return "Neither a TR complexity nor a TD estimate";
}

function blockedWhy(epic: Card | undefined, row: Row, cards: Card[]) {
	if (row.blocked === "epic") return `its own blocked flag says "${epic?.blocked ?? ""}"`;
	const open = openWorkOf(cards);
	return `every open feature or bug card on it is blocked: ${open.map((card) => `${card.id}, "${card.blocked}"`).join("; ")}`;
}

function blockedForecast(row: Row) {
	return row.begin != null
		? `it gives up its track, and the forecast assumes it is unblocked by ${short(row.begin)}, when the next track frees after the epics that took its place`
		: "it gives up its track, and has no forecast until a track can take it";
}

function runTitle(row: Row) {
	const { complexity, fromEstimate, points, tickets, sized, unsized } = row.remaining;
	const onEstimates = tickets - sized - unsized;
	const shown = (counted: number, value: number) => (counted > 0 ? figure(value) : "-");
	return `${shown(sized + onEstimates, points)} pts left, ${shown(sized, complexity)} on TR complexity and ${shown(onEstimates, fromEstimate)} on TD estimates. ${estimatesTitle(row.remaining)}`;
}

function refinementText(refinement: Refinement) {
	return refinement.source === "measured"
		? `${refinement.days} working days on average from leaving Backlog to Ready for Dev, over ${refinement.epics} ${refinement.epics === 1 ? "epic" : "epics"}`
		: `${refinement.days} working days, a default, as no epic has gone from leaving Backlog to Ready for Dev yet`;
}

function tracksText(count: number) {
	if (count === 0) return "no tracks";
	return count === 1 ? "1 track" : `${count} tracks`;
}

function speedFrom(speed: AverageSpeed) {
	const counted =
		speed.source === "measured"
			? `${figure(speed.points)} pts from ${speed.tickets} ${speed.tickets === 1 ? "ticket" : "tickets"} over ${speed.days} working ${speed.days === 1 ? "day" : "days"}, ${figure(speed.perDay)} a day`
			: `nothing with TR complexity done in the last ${AVERAGE_SPEED_DAYS} working days`;
	const beside = [
		speed.uncounted > 0 ? `${speed.uncounted} done without complexity` : "",
		speed.timeboxes > 0 ? `${speed.timeboxes} ${speed.timeboxes === 1 ? "timebox" : "timeboxes"}` : "",
	].filter(Boolean);
	return [counted, ...beside].join(" + ");
}

function speedText(speed: TrackSpeed) {
	if (speed.source === "overall") {
		const from =
			speed.speed.source === "measured" ? "measured" : speed.speed.source === "sprint" ? "sprint speed" : "default";
		return {
			short: "overall average, no history",
			title: `No ticket of this project with a TR complexity was done in the last ${AVERAGE_SPEED_DAYS} working days, so it takes the board's overall average speed a track (${from})`,
		};
	}
	const split =
		speed.inProgress > 1
			? `, split across the ${figure(speed.inProgress)} epics it had in progress on average`
			: ", with no more than one epic in progress on average";
	return {
		short: "measured",
		title: `${figure(speed.speed.perWeek)} pts a week for the project (${speedFrom(speed.speed)})${split}, so ${figure(speed.perWeek)} a track`,
	};
}

function TracksControl({
	name,
	count,
	speed,
	onChange,
}: {
	name: string;
	count: number;
	speed: TrackSpeed;
	onChange: (count: number) => void;
}) {
	const label = speedText(speed);
	return (
		<span className="plan-tracks">
			<span className="plan-tracks-step" role="group" aria-label={`Tracks of ${name}`}>
				<button
					type="button"
					className="quiet"
					disabled={count <= 0}
					aria-label={`One track fewer for ${name}`}
					title="One track fewer - the lowest epic in progress pauses if there are more than tracks, and with none its epics are not scheduled"
					onClick={() => onChange(count - 1)}
				>
					−
				</button>
				<span
					className={`plan-tracks-count${count === 0 ? " none" : ""}`}
					title={
						count === 0
							? "It has no share of the board's tracks, so none of its epics is scheduled"
							: "How many of its epics run at once, from today on"
					}
				>
					{tracksText(count)}
				</span>
				<button
					type="button"
					className="quiet"
					aria-label={`One track more for ${name}`}
					title="One track more, from today on"
					onClick={() => onChange(count + 1)}
				>
					+
				</button>
			</span>
			<span className={`plan-team-speed${speed.source === "overall" ? " fallback" : ""}`} title={label.title}>
				{speed.source === "measured" ? `${figure(speed.speed.perWeek)} pts/wk · ` : ""}
				{figure(speed.perWeek)} a track · {label.short}
			</span>
		</span>
	);
}

function TrackPick({
	epic,
	row,
	count,
	onPick,
}: {
	epic: Card;
	row: Row;
	count: number;
	onPick: (value: string) => void;
}) {
	const pinned = row.pin != null && !row.pinIgnored;
	const title = row.pinIgnored
		? `Pinned to track ${row.pin}, past the ${tracksText(count)} its project has, so the plan places it itself`
		: pinned
			? `Pinned to track ${row.pin} - it waits for that track to free`
			: row.track == null
				? "Not on a track - it has no points left to schedule"
				: `Runs on track ${row.track}, the first one free to the highest epic ready for it`;
	return (
		<label className={`plan-track-pick${pinned ? " pinned" : ""}${row.pinIgnored ? " warn" : ""}`} title={title}>
			{row.pinIgnored && <Icon name="plan" />}
			{pinned ? `Pinned ${row.pin}` : row.track == null ? "No track" : `Track ${row.track}`}
			<select aria-label={`Track of ${epic.id}`} value={row.pin ?? ""} onChange={(event) => onPick(event.target.value)}>
				<option value="">Placed by the plan</option>
				{Array.from({ length: count }, (_, index) => (
					<option key={index + 1} value={index + 1}>
						Pin to track {index + 1}
					</option>
				))}
				{row.pinIgnored && <option value={row.pin ?? ""}>Pinned to track {row.pin} - past its tracks</option>}
			</select>
		</label>
	);
}

function PlanPanel({
	epic,
	cards,
	lists,
	handlers,
	notice,
	onDismiss,
	onClose,
	onSaved,
}: {
	epic: Card;
	cards: Card[];
	lists: Lists;
	handlers: Handlers;
	notice: Notice;
	onDismiss: () => void;
	onClose: () => void;
	onSaved: (record: Card, undo?: Span, label?: string) => void;
}) {
	const panel = useRef<HTMLElement>(null);
	useEffect(() => {
		panel.current?.scrollTo({ top: 0 });
	}, [epic.id]);
	return (
		<aside className="peek" ref={panel} aria-label={`${epic.id} details`}>
			<header className="peek-head">
				<span className="ident">{epic.id}</span>
				<span className="peek-actions">
					<Link href={`/epics?open=${epic.id}`} className="quiet-link">
						On the Epics board
					</Link>
					<Link href={`/card/${epic.id}`} className="quiet-link">
						Open
					</Link>
					<button type="button" className="quiet" onClick={onClose} title="Close (Esc)" aria-keyshortcuts="Escape">
						Close
					</button>
				</span>
			</header>
			{notice && (
				<p className="notice error" role="alert">
					<span>{notice.text}</span>
					<button type="button" className="quiet" onClick={onDismiss}>
						Dismiss
					</button>
				</p>
			)}
			{epic.icon && <span className="page-icon">{epic.icon}</span>}
			<Title
				id={epic.id}
				className="peek-title"
				value={epic.name}
				onCommit={(name) => handlers.onEdit("name", name, { name })}
			/>
			<Fields record={epic} lists={lists} handlers={handlers} />
			<EstimateFacts estimates={estimatesOf(cards)} left />
			<section className="timeline">
				<h3>
					Cards <span className="count">{cards.length}</span>
				</h3>
				<p className="epic-progress">
					<ProgressMeter progress={progressOf(cards)} wide />
				</p>
				<ol>
					{cards.map((card) => (
						<li key={card.id}>
							<span className={`dot phase-${phaseOf(card.status)}`} aria-hidden="true" />
							<Link href={`/?open=${card.id}`}>{card.name}</Link>
							<span className="ident" title={cardPointsTitle(card)}>
								{card.type === "Timebox" ? "timebox" : pointsOf(card) == null ? "unsized" : `${pointsOf(card)} pts`}
							</span>
						</li>
					))}
				</ol>
			</section>
			<Stages record={epic} />
			<Content id={epic.id} revision={epic.updated} onSaved={onSaved} />
		</aside>
	);
}

function MilestoneEditor({
	editing,
	onChange,
	onSave,
	onRemove,
	onClose,
	busy,
}: {
	editing: NonNullable<Editing>;
	onChange: (editing: NonNullable<Editing>) => void;
	onSave: () => void;
	onRemove: () => void;
	onClose: () => void;
	busy: boolean;
}) {
	return (
		<form
			className="plan-popover plan-milestone-form"
			aria-label={editing.id ? `Milestone ${editing.id}` : "New milestone"}
			onSubmit={(event) => {
				event.preventDefault();
				onSave();
			}}
			onKeyDown={(event) => {
				if (event.key === "Escape") {
					event.stopPropagation();
					onClose();
				}
			}}
		>
			<strong>{editing.id ? `Milestone ${editing.id}` : "New milestone"}</strong>
			<input
				aria-label="Milestone name"
				placeholder="Launch, a review, a release…"
				value={editing.name}
				ref={(input) => {
					if (input && !editing.id && !editing.name) input.focus();
				}}
				onChange={(event) => onChange({ ...editing, name: event.target.value })}
			/>
			<input
				type="date"
				aria-label="Milestone date"
				required
				value={editing.date}
				onChange={(event) => onChange({ ...editing, date: event.target.value })}
			/>
			<span className="plan-popover-actions">
				{editing.id && (
					<button type="button" className="quiet danger" disabled={busy} onClick={onRemove}>
						Remove
					</button>
				)}
				<span className="spacer" />
				<button type="button" className="quiet" onClick={onClose}>
					Cancel
				</button>
				<button type="submit" disabled={busy || !editing.name.trim() || !editing.date}>
					{editing.id ? "Save" : "Add"}
				</button>
			</span>
		</form>
	);
}

type BreakDraft = { from: string; to: string; name: string };

function BreaksEditor({
	breaks,
	busy,
	error,
	onAdd,
	onRemove,
	onClose,
}: {
	breaks: Break[];
	busy: boolean;
	error: string | null;
	onAdd: (draft: BreakDraft) => void;
	onRemove: (id: string) => void;
	onClose: () => void;
}) {
	const [draft, setDraft] = useState<BreakDraft>({ from: "", to: "", name: "" });
	useEffect(() => setDraft({ from: "", to: "", name: "" }), [breaks]);
	return (
		<form
			className="plan-popover plan-milestone-form plan-breaks-form"
			aria-label="Breaks"
			onSubmit={(event) => {
				event.preventDefault();
				onAdd(draft);
			}}
			onKeyDown={(event) => {
				if (event.key === "Escape") {
					event.stopPropagation();
					onClose();
				}
			}}
		>
			<strong>Breaks</strong>
			{breaks.length === 0 ? (
				<span className="plan-speed-from">No breaks - nothing is left out of the speed or the forecast</span>
			) : (
				<ul className="plan-breaks">
					{breaks.map((one) => (
						<li key={one.id}>
							<span>
								{one.name || "Break"} · {short(dayOf(one.from) ?? 0)} to {short(dayOf(one.to) ?? 0)}
							</span>
							<button
								type="button"
								className="quiet danger"
								disabled={busy}
								aria-label={`Remove the break ${one.name || one.id}`}
								onClick={() => onRemove(one.id)}
							>
								Remove
							</button>
						</li>
					))}
				</ul>
			)}
			<input
				aria-label="Break name"
				placeholder="Leave, a holiday…"
				value={draft.name}
				onChange={(event) => setDraft({ ...draft, name: event.target.value })}
			/>
			<span className="plan-breaks-days">
				<input
					type="date"
					aria-label="First day of the break"
					required
					value={draft.from}
					onChange={(event) => setDraft({ ...draft, from: event.target.value, to: draft.to || event.target.value })}
				/>
				<input
					type="date"
					aria-label="Last day of the break"
					required
					min={draft.from || undefined}
					value={draft.to}
					onChange={(event) => setDraft({ ...draft, to: event.target.value })}
				/>
			</span>
			{error && (
				<span className="notice error" role="alert">
					{error}
				</span>
			)}
			<span className="plan-popover-actions">
				<span className="spacer" />
				<button type="button" className="quiet" onClick={onClose}>
					Close
				</button>
				<button type="submit" disabled={busy || !draft.from || !draft.to || draft.to < draft.from}>
					Add
				</button>
			</span>
		</form>
	);
}

export function Plan({
	initial,
	cards,
	milestones: initialMilestones,
	tracks: initialTracks,
	breaks: initialBreaks,
	projects,
	sprints,
	today: todayText,
	lists,
}: {
	initial: Card[];
	cards: Card[];
	milestones: Card[];
	tracks: number;
	breaks: Break[];
	projects: Project[];
	sprints: Pick<Card, "start" | "end" | "speed">[];
	today: string;
	lists: Lists;
}) {
	const router = useRouter();
	const hydrated = useHydrated();
	const [epics, setEpics] = useState(initial);
	const [milestones, setMilestones] = useState(initialMilestones);
	const [prefs, setPrefs] = useState<Prefs>({ scale: "weeks", grouped: true });
	const [drag, setDrag] = useState<Drag | null>(null);
	const [rowDragging, setRowDragging] = useState<string | null>(null);
	const [openId, setOpenId] = useState<string | null>(null);
	const [notice, setNotice] = useState<Notice>(null);
	const [toast, setToast] = useState<Undoable | null>(null);
	const [undoing, setUndoing] = useState(false);
	const [editing, setEditing] = useState<Editing>(null);
	const [legendOpen, setLegendOpen] = useState(false);
	const [finishing, setFinishing] = useState<Finishing | null>(null);
	const [pending, setPending] = useState<Set<string>>(new Set());
	const [trackCounts, setTrackCounts] = useState<Record<string, number>>({});
	const [boardCount, setBoardCount] = useState(initialTracks);
	const [breaks, setBreaks] = useState(initialBreaks);
	const [breaksOpen, setBreaksOpen] = useState(false);
	const [breakError, setBreakError] = useState<string | null>(null);
	const [saving, startTransition] = useTransition();
	const scroller = useRef<HTMLDivElement>(null);
	const dndId = useId();
	const live = useRef({ ppd: SCALES.weeks as number, first: 0 });
	const latest = useRef<Record<string, number>>({});
	const loaded = useRef(false);

	const pendingNow = useRef(pending);
	pendingNow.current = pending;
	useEffect(
		() =>
			setEpics((current) =>
				initial.map((epic) =>
					pendingNow.current.has(epic.id) ? (current.find((one) => one.id === epic.id) ?? epic) : epic,
				),
			),
		[initial],
	);
	useEffect(() => setMilestones(initialMilestones), [initialMilestones]);
	useEffect(() => setTrackCounts({}), [projects]);
	useEffect(() => setBoardCount(initialTracks), [initialTracks]);
	useEffect(() => setBreaks(initialBreaks), [initialBreaks]);

	useEffect(() => {
		setPrefs(loadPrefs());
		const opening = new URLSearchParams(window.location.search).get("open")?.toUpperCase();
		if (opening && kindOf(opening) === "epic") setOpenId(opening);
		loaded.current = true;
	}, []);

	useEffect(() => {
		if (!loaded.current) return;
		const url = new URL(window.location.href);
		if (openId) url.searchParams.set("open", openId);
		else url.searchParams.delete("open");
		if (url.href !== window.location.href) window.history.replaceState(null, "", url);
	}, [openId]);

	const today = dayOf(todayText) ?? 0;
	const now = useMemo(() => new Date(), [cards]);
	const projectOf = useMemo(() => Object.fromEntries(projects.map((project) => [project.id, project])), [projects]);
	const speeds = useMemo(
		() =>
			trackSpeedsOf(
				cards,
				epics,
				projects.map((project) => project.id),
				sprints,
				now,
				breaks,
			),
		[cards, epics, projects, sprints, now, breaks],
	);
	const rate = speeds.overall.speed;
	const tracksOf = (team: string) => trackCounts[team] ?? projectOf[team]?.tracks ?? 0;
	const teams = useMemo(() => {
		const all: Record<string, Team> = {};
		for (const team of projects.map((project) => project.id)) {
			all[team] = { tracks: tracksOf(team), perWeek: (speeds.teams[team] ?? speeds.overall).perWeek };
		}
		return all;
	}, [projects, speeds, trackCounts, projectOf]);
	const teamName = (team: string) => projectOf[team]?.name ?? team;
	const fallbackOf = (team: string) => (speeds.teams[team] ?? speeds.overall).source === "overall";
	const counts = (team: string) => projectOf[team]?.status !== "Done";
	const allocated = projects.reduce((sum, project) => sum + (counts(project.id) ? tracksOf(project.id) : 0), 0);
	const homeless = epics.filter((epic) => !epic.project || !projectOf[epic.project]);

	const shown = useMemo(() => {
		if (!drag || drag.mode === "milestone") return epics;
		const next = moved(drag);
		return epics.map((epic) =>
			epic.id === drag.id
				? {
						...epic,
						start: next.start == null ? null : dayText(next.start),
						target: next.target == null ? null : dayText(next.target),
					}
				: epic,
		);
	}, [epics, drag]);

	const refinement = useMemo(() => refinementOf(epics, daysOff(breaks)), [epics, breaks]);
	const rows = useMemo(
		() => planOf(shown, cards, teams, today, refinement, breaks),
		[shown, cards, teams, today, refinement, breaks],
	);
	const committedRows = useMemo(
		() => planOf(epics, cards, teams, today, refinement, breaks),
		[epics, cards, teams, today, refinement, breaks],
	);
	const spans = breaks.flatMap((one) => {
		const from = dayOf(one.from);
		const to = dayOf(one.to);
		return from != null && to != null && to >= from ? [{ ...one, first: from, last: to }] : [];
	});
	const breakTitle = (one: (typeof spans)[number]) =>
		`${one.name || "Break"} · ${long(one.first)} to ${long(one.last)} - nothing is refined or delivered on these days`;

	const span = useMemo(
		() =>
			spanOf(
				[
					...Object.values(committedRows).flatMap((row) => [
						row.refineStart,
						row.refineEnd,
						row.target,
						row.projected,
						row.doneDay,
					]),
					...milestones.map((milestone) => dayOf(milestone.date)),
				],
				today,
			),
		[committedRows, milestones, today],
	);
	const frozen = useRef(span);
	if (!drag) frozen.current = span;
	const view = drag ? frozen.current : span;

	const ppd = SCALES[prefs.scale];
	live.current = { ppd, first: view.first };
	const width = (view.last - view.first + 1) * ppd;
	const x = (day: number) => (day - view.first) * ppd;

	useEffect(() => {
		if (!hydrated) return;
		toToday();
	}, [hydrated, prefs.scale]);

	function toToday() {
		const box = scroller.current;
		if (!box) return;
		const left = box.querySelector<HTMLElement>(".plan-left")?.offsetWidth ?? 0;
		box.scrollLeft = Math.max(0, x(today) - (box.clientWidth - left) * 0.3);
	}

	function changePrefs(change: Partial<Prefs>) {
		const next = { ...prefs, ...change };
		setPrefs(next);
		savePrefs(next);
	}

	const cardsOf = useMemo(() => {
		const by: Record<string, Card[]> = {};
		for (const card of cards) if (card.epic) (by[card.epic] ??= []).push(card);
		return by;
	}, [cards]);

	const groups = useMemo(() => {
		const ordered = planOrder(epics.filter((epic) => epic.project && projectOf[epic.project]));
		if (!prefs.grouped)
			return [{ id: "all", team: null as string | null, name: "", icon: null as string | null, epics: ordered }];
		const keys = [...new Set(ordered.map((epic) => epic.project as string))];
		keys.sort((a, b) => {
			const first = projectOf[a];
			const second = projectOf[b];
			return (
				(first.priority ?? Number.POSITIVE_INFINITY) - (second.priority ?? Number.POSITIVE_INFINITY) ||
				first.name.localeCompare(second.name)
			);
		});
		const last = Number.POSITIVE_INFINITY;
		const placed = (epic: Card) => {
			const row = committedRows[epic.id];
			return [row?.done ? 1 : 0, row?.track ?? last, row?.refineStart ?? row?.begin ?? row?.doneDay ?? last];
		};
		const cascade = (list: Card[]) =>
			[...list].sort((a, b) => {
				const first = placed(a);
				const second = placed(b);
				return first[0] - second[0] || first[1] - second[1] || first[2] - second[2];
			});
		return keys.map((key) => ({
			id: key,
			team: key as string | null,
			name: projectOf[key].name,
			icon: projectOf[key].icon ?? null,
			epics: cascade(ordered.filter((epic) => epic.project === key)),
		}));
	}, [epics, prefs.grouped, projectOf, committedRows]);

	const visualOrder = groups.flatMap((group) => group.epics.map((epic) => ({ id: epic.id, group: group.id })));

	const open = openId ? (epics.find((epic) => epic.id === openId) ?? null) : null;

	useEffect(() => {
		function onKey(event: KeyboardEvent) {
			if (event.key !== "Escape" || typingIn(event.target)) return;
			if (editing) setEditing(null);
			else if (openId && confirmDiscard()) setOpenId(null);
		}
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	}, [editing, openId]);

	function markPending(id: string, on: boolean) {
		setPending((current) => {
			const next = new Set(current);
			if (on) next.add(id);
			else next.delete(id);
			return next;
		});
	}

	function apply(id: string, optimistic: Partial<Card>, request: () => Promise<Outcome>, label: string) {
		const before = epics.find((epic) => epic.id === id);
		if (!before) return;
		setNotice(null);
		setToast(null);
		setEpics((current) => current.map((epic) => (epic.id === id ? { ...epic, ...optimistic } : epic)));
		markPending(id, true);
		const mine = (latest.current[id] ?? 0) + 1;
		latest.current[id] = mine;
		startTransition(async () => {
			const result = await request();
			if (latest.current[id] !== mine) {
				if (result.error) setNotice({ id, text: `${id}: ${result.error}` });
				return;
			}
			markPending(id, false);
			if (result.error) {
				setEpics((current) => current.map((epic) => (epic.id === id ? before : epic)));
				setNotice({ id, text: `${id}: ${result.error}` });
				if (result.archived || result.moved) router.refresh();
				return;
			}
			const fresh = result.record;
			if (fresh) {
				setEpics((current) => current.map((epic) => (epic.id === id ? fresh : epic)));
				setToast(undoable(fresh.id, result.undo, label, result.more));
			}
			router.refresh();
		});
	}

	function handlersFor(epic: Card): Handlers {
		return {
			onMove: (column) => moveEpic(epic, column),
			onEdit: (field, value, change) =>
				apply(epic.id, change, () => editCard(epic.id, field, value), `Changed the ${fieldName(field)} of ${epic.id}`),
			onLink: () => {},
			onOpen: (id) => {
				if (kindOf(id) === "epic") show(id);
				else router.push(`/?open=${id}`);
			},
		};
	}

	function show(id: string | null) {
		if (id !== openId && !confirmDiscard()) return;
		setOpenId(id);
	}

	function moveEpic(epic: Card, column: string, checked = false) {
		if (!checked && column === "Epic Done" && epic.status !== column) {
			const open = openTickets(cardsOf[epic.id] ?? []);
			if (open.length > 0) {
				setFinishing({ id: epic.id, name: epic.name, open });
				return;
			}
		}
		apply(epic.id, movedTo(column), () => dropCard(epic.id, column), `Moved ${epic.id} to ${column}`);
	}

	function finish(chosen: Finishing) {
		setNotice(null);
		setToast(null);
		startTransition(async () => {
			const result = await finishEpic(
				chosen.id,
				chosen.open.map((card) => card.id),
			);
			setFinishing(null);
			const fresh = result.record;
			if (fresh) setEpics((current) => current.map((epic) => (epic.id === chosen.id ? fresh : epic)));
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

	function pickStatus(epic: Card, value: string) {
		if (value === DONE) {
			moveEpic(epic, "Epic Done");
			return;
		}
		apply(
			epic.id,
			{ confidence: value || null },
			() => editCard(epic.id, "confidence", value),
			value ? `Marked ${epic.id} ${STATUSES[value].label}` : `Cleared the status of ${epic.id}`,
		);
	}

	function pickTrack(epic: Card, value: string) {
		apply(
			epic.id,
			{ track: value ? Number(value) : null },
			() => editCard(epic.id, "track", value),
			value ? `Pinned ${epic.id} to track ${value}` : `Let the plan place ${epic.id} on a track`,
		);
	}

	function changeTracks(team: string, count: number) {
		const before = tracksOf(team);
		if (count < 0 || count === before) return;
		if (count > before && counts(team) && allocated - before + count > boardCount) {
			setToast(null);
			setNotice({
				id: "",
				text: `${teamName(team)} cannot take ${tracksText(count)}: the projects' shares would add up to ${allocated - before + count}, over the board's ${tracksText(boardCount)}. Raise the board's tracks first, or take one from another project.`,
			});
			return;
		}
		const label =
			count === 0 ? `Took every track from ${teamName(team)}` : `Gave ${teamName(team)} ${tracksText(count)}`;
		setNotice(null);
		setToast(null);
		setTrackCounts((current) => ({ ...current, [team]: count }));
		startTransition(async () => {
			const result = await editCard(team, "tracks", count === 0 ? "" : String(count));
			if (result.error) {
				setTrackCounts((current) => ({ ...current, [team]: before }));
				setNotice({ id: "", text: `${teamName(team)}: ${result.error}` });
				return;
			}
			setToast(undoable(team, result.undo, label));
			router.refresh();
		});
	}

	function changeBoardTracks(count: number) {
		const before = boardCount;
		if (count < 1 || count === before) return;
		setToast(null);
		if (count < allocated) {
			setNotice({
				id: "",
				text: `The projects' shares add up to ${allocated}, so the board needs at least ${tracksText(allocated)} - take a track from a project first.`,
			});
			return;
		}
		setNotice(null);
		setBoardCount(count);
		startTransition(async () => {
			const result = await setBoardTracks(count);
			if (result.error) {
				setBoardCount(before);
				setNotice({ id: "", text: `The board's tracks: ${result.error}` });
				return;
			}
			if (result.tracks) setBoardCount(result.tracks);
			router.refresh();
		});
	}

	function addBreakFrom(draft: BreakDraft) {
		setBreakError(null);
		startTransition(async () => {
			const result = await saveBreak(draft.from, draft.to, draft.name);
			if (result.error || !result.breaks) {
				setBreakError(`Could not add the break: ${result.error ?? "board-card added nothing"}`);
				return;
			}
			setBreaks(result.breaks);
		});
	}

	function removeBreakOf(id: string) {
		setBreakError(null);
		startTransition(async () => {
			const result = await dropBreak(id);
			if (result.error || !result.breaks) {
				setBreakError(`Could not remove the break: ${result.error ?? "board-card removed nothing"}`);
				return;
			}
			setBreaks(result.breaks);
		});
	}

	function commitTarget(id: string, target: number | null, label: string) {
		const epic = epics.find((one) => one.id === id);
		if (!epic) return;
		const targetText = target == null ? "" : dayText(target);
		if (targetText === (epic.target ?? "")) return;
		apply(id, { target: targetText || null }, () => editCard(id, "target", targetText), label);
	}

	function targetLabel(id: string, target: number | null, mode: Mode) {
		const day = target == null ? "nothing" : short(target);
		return mode === "draw" ? `Gave ${id} a target of ${day}` : `Moved the target of ${id} to ${day}`;
	}

	function dropped(state: Drag) {
		if (state.mode === "milestone") {
			const milestone = milestones.find((one) => one.id === state.id);
			if (!milestone || state.start == null) return;
			if (!state.moved) {
				setEditing({ id: milestone.id, name: milestone.name, date: milestone.date ?? "" });
				return;
			}
			const date = dayText(state.start + state.delta);
			editMilestone(milestone.id, "date", date, `Moved ${milestone.name} to ${short(state.start + state.delta)}`);
			return;
		}
		if (!state.moved) {
			if (state.mode !== "draw") show(state.id);
			return;
		}
		const next = moved(state);
		commitTarget(state.id, next.target, targetLabel(state.id, next.target, state.mode));
	}

	function beginDrag(event: ReactPointerEvent<HTMLElement>, base: Omit<Drag, "delta" | "moved">) {
		if (event.button !== 0) return;
		event.stopPropagation();
		const element = event.currentTarget;
		const pointer = event.pointerId;
		const x0 = event.clientX;
		const y0 = event.clientY;
		const touch = event.pointerType === "touch";
		const state: Drag = { ...base, delta: 0, moved: false };
		let active = false;
		let timer = 0;
		if (!touch) event.preventDefault();

		function activate() {
			active = true;
			try {
				element.setPointerCapture(pointer);
			} catch {}
			setDrag({ ...state });
		}
		function onMove(move: PointerEvent) {
			if (move.pointerId !== pointer) return;
			if (!active) {
				if (touch && Math.hypot(move.clientX - x0, move.clientY - y0) > 8) finish(false, false);
				return;
			}
			const delta = Math.round((move.clientX - x0) / live.current.ppd);
			if (delta === state.delta) return;
			state.delta = delta;
			state.moved = state.moved || delta !== 0;
			setDrag({ ...state });
		}
		function onUp(up: PointerEvent) {
			if (up.pointerId !== pointer) return;
			finish(true, !active);
		}
		function onCancel() {
			finish(false, false);
		}
		function onKey(key: KeyboardEvent) {
			if (key.key === "Escape") finish(false, false);
		}
		function blockScroll(scroll: TouchEvent) {
			if (active) scroll.preventDefault();
		}
		function finish(commit: boolean, tap: boolean) {
			window.clearTimeout(timer);
			window.removeEventListener("pointermove", onMove);
			window.removeEventListener("pointerup", onUp);
			window.removeEventListener("pointercancel", onCancel);
			window.removeEventListener("keydown", onKey);
			window.removeEventListener("touchmove", blockScroll);
			setDrag(null);
			if (tap) dropped({ ...state, moved: false });
			else if (commit) dropped(state);
		}
		window.addEventListener("pointermove", onMove);
		window.addEventListener("pointerup", onUp);
		window.addEventListener("pointercancel", onCancel);
		window.addEventListener("keydown", onKey);
		window.addEventListener("touchmove", blockScroll, { passive: false });
		if (touch) timer = window.setTimeout(activate, HOLD);
		else activate();
	}

	function dayAt(event: ReactPointerEvent<HTMLElement>) {
		const box = event.currentTarget.getBoundingClientRect();
		return view.first + Math.floor((event.clientX - box.left) / ppd);
	}

	function reorder(id: string, overId: string, below: boolean) {
		if (id === overId) return;
		const order = planOrder(epics);
		const moving = order.find((epic) => epic.id === id);
		if (!moving) return;
		const rest = order.filter((epic) => epic.id !== id);
		const at = rest.findIndex((epic) => epic.id === overId) + (below ? 1 : 0);
		const next = [...rest.slice(0, at), moving, ...rest.slice(at)];
		const before = next[at - 1];
		const after = next[at + 1];
		let ranks: Ranked[] = [];
		const between =
			before?.rank != null && after?.rank != null
				? (before.rank + after.rank) / 2
				: before?.rank != null && !after
					? before.rank + 1
					: after?.rank != null && !before
						? after.rank - 1
						: null;
		const roomy =
			between != null &&
			(before?.rank == null || Math.abs(between - before.rank) > 0.00001) &&
			(after?.rank == null || Math.abs(between - after.rank) > 0.00001);
		if (roomy && between != null) ranks = [{ id, rank: between }];
		else
			ranks = next
				.slice(0, Math.max(at + 1, order.filter((epic) => epic.rank != null).length))
				.map((epic, index) => ({ id: epic.id, rank: index + 1 }))
				.filter((rank) => order.find((epic) => epic.id === rank.id)?.rank !== rank.rank);
		const rankOf = Object.fromEntries(ranks.map((rank) => [rank.id, rank.rank]));
		const earlier = epics;
		setNotice(null);
		setToast(null);
		setEpics((current) => current.map((epic) => (epic.id in rankOf ? { ...epic, rank: rankOf[epic.id] } : epic)));
		for (const rank of ranks) markPending(rank.id, true);
		startTransition(async () => {
			const result = await rankPlan(ranks);
			for (const rank of ranks) markPending(rank.id, false);
			const fresh = new Map(result.records.flatMap(({ from, record }) => (record ? [[from, record]] : [])));
			setEpics((current) =>
				current.map(
					(epic) =>
						fresh.get(epic.id) ?? (epic.id in rankOf ? (earlier.find((one) => one.id === epic.id) ?? epic) : epic),
				),
			);
			if (result.errors.length > 0) setNotice({ id: "", text: result.errors.join("; ") });
			if (result.undo.length > 0)
				setToast(toastOf(`Moved ${id} ${below ? "below" : "above"} ${overId} in the plan`, result.undo));
			router.refresh();
		});
	}

	function groupOf(id: string) {
		return visualOrder.find((entry) => entry.id === id)?.group;
	}

	function onRowDragEnd(event: DragEndEvent) {
		setRowDragging(null);
		const id = String(event.active.id).slice(4);
		const overId = event.over ? String(event.over.id).slice(4) : null;
		if (!overId || overId === id) return;
		if (groupOf(id) !== groupOf(overId)) {
			setNotice({
				id: "",
				text: `${id} belongs to another project - set its project on the epic to move it into that group`,
			});
			return;
		}
		const from = visualOrder.findIndex((entry) => entry.id === id);
		const to = visualOrder.findIndex((entry) => entry.id === overId);
		reorder(id, overId, to > from);
	}

	function editMilestone(id: string, field: string, value: string, label: string) {
		const before = milestones.find((one) => one.id === id);
		if (!before) return;
		setNotice(null);
		setToast(null);
		setMilestones((current) => current.map((one) => (one.id === id ? { ...one, [field]: value } : one)));
		startTransition(async () => {
			const result = await editCard(id, field, value);
			if (result.error) {
				setMilestones((current) => current.map((one) => (one.id === id ? before : one)));
				setNotice({ id: "", text: `${id}: ${result.error}` });
				return;
			}
			const fresh = result.record;
			if (fresh) {
				setMilestones((current) => current.map((one) => (one.id === id ? fresh : one)));
				setToast(undoable(id, result.undo, label));
			}
			router.refresh();
		});
	}

	function saveMilestone() {
		if (!editing) return;
		const { id, name, date } = editing;
		if (!id) {
			startTransition(async () => {
				const result = await createMilestone(name, date);
				if (result.error || !result.record) {
					setNotice({ id: "", text: `Could not add the milestone: ${result.error ?? "board-card made nothing"}` });
					return;
				}
				const fresh = result.record;
				setMilestones((current) => [...current, fresh]);
				setEditing(null);
				setToast(toastOf(`Added ${fresh.name} on ${short(dayOf(date) ?? today)}`));
				router.refresh();
			});
			return;
		}
		const milestone = milestones.find((one) => one.id === id);
		setEditing(null);
		if (!milestone) return;
		if (name.trim() && name.trim() !== milestone.name)
			editMilestone(id, "name", name.trim(), `Renamed ${id} to ${name.trim()}`);
		if (date && date !== milestone.date)
			editMilestone(id, "date", date, `Moved ${name.trim()} to ${short(dayOf(date) ?? today)}`);
	}

	function dropMilestone() {
		const id = editing?.id;
		if (!id) return;
		const milestone = milestones.find((one) => one.id === id);
		setEditing(null);
		setMilestones((current) => current.filter((one) => one.id !== id));
		startTransition(async () => {
			const result = await removeMilestone(id);
			if (result.error) {
				if (milestone) setMilestones((current) => [...current, milestone]);
				setNotice({ id: "", text: `${id}: ${result.error}` });
				return;
			}
			setToast(undoable(id, result.undo, `Removed ${milestone?.name ?? id} from the plan`));
			router.refresh();
		});
	}

	function undo(shownToast: Undoable) {
		setUndoing(true);
		setNotice(null);
		startTransition(async () => {
			const failures: string[] = [];
			for (const change of shownToast.changes) {
				const result = await undoChange(change.id, { since: change.since, until: change.until });
				if (result.error) {
					failures.push(result.error);
					continue;
				}
				const fresh = result.record;
				if (!fresh) continue;
				if (kindOf(fresh.id) === "epic")
					setEpics((current) => current.map((epic) => (epic.id === change.id ? fresh : epic)));
				if (fresh.id.startsWith("MS-"))
					setMilestones((current) =>
						current.some((one) => one.id === fresh.id)
							? current.map((one) => (one.id === fresh.id ? fresh : one))
							: [...current, fresh],
					);
			}
			setUndoing(false);
			setToast((current) => (current?.key === shownToast.key ? null : current));
			if (failures.length > 0) setNotice({ id: "", text: `Could not undo: ${failures.join("; ")}` });
			router.refresh();
		});
	}

	const sensors = useSensors(
		useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
		useSensor(TouchSensor, { activationConstraint: { delay: 220, tolerance: 6 } }),
	);

	const months = useMemo(() => {
		const list: { day: number; label: string }[] = [];
		const first = new Date(view.first * DAY);
		let cursor = Date.UTC(first.getUTCFullYear(), first.getUTCMonth(), 1) / DAY;
		while (cursor <= view.last) {
			const date = new Date(cursor * DAY);
			const label = date.toLocaleDateString(undefined, {
				month: prefs.scale === "weeks" ? "long" : "short",
				timeZone: "UTC",
				...(date.getUTCMonth() === 0 || list.length === 0 ? { year: "numeric" } : {}),
			});
			list.push({ day: Math.max(cursor, view.first), label });
			cursor = Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1) / DAY;
		}
		if (list.length > 1 && (list[1].day - list[0].day) * SCALES[prefs.scale] < 64) {
			const year = new Date(list[0].day * DAY).getUTCFullYear();
			list.shift();
			if (!/\d{4}/.test(list[0].label)) list[0].label = `${list[0].label} ${year}`;
		}
		return list;
	}, [view.first, view.last, prefs.scale]);

	const mondays = useMemo(() => {
		if (prefs.scale !== "weeks") return [];
		const list: number[] = [];
		for (let day = mondayOf(view.first); day <= view.last; day += 7) if (day >= view.first) list.push(day);
		return list;
	}, [view.first, view.last, prefs.scale]);

	const open_rows = Object.values(committedRows).filter((row) => !row.done);
	const pointsLeft = open_rows.reduce((sum, row) => sum + row.remaining.points, 0);
	const unsized = open_rows.reduce((sum, row) => sum + row.remaining.unsized, 0);
	const lateCount = Object.values(committedRows).filter((row) => !row.done && row.late > 0).length;
	const planEnd = Math.max(...open_rows.map((row) => row.projected ?? Number.NEGATIVE_INFINITY));
	const rateTitle =
		rate.source === "measured"
			? `The TR complexity of the tickets finished on the last ${rate.days} working days, Monday to Friday outside a break, divided by those days and shown as a week of five - a working day that finished nothing still counts, a ticket finished at a weekend or in a break is left out, and a ticket done without a complexity, or a timebox, is counted beside it and not in it`
			: rate.source === "sprint"
				? `No ticket with a TR complexity was finished on the last ${AVERAGE_SPEED_DAYS} working days, so this is the current sprint's speed a day times five`
				: `No ticket with a TR complexity was finished on the last ${AVERAGE_SPEED_DAYS} working days and no sprint has a speed, so this is the default`;

	const nameOf = (id: string) => epics.find((epic) => epic.id === id)?.name ?? id;
	const trackNotes = Object.values(committedRows).flatMap((row) => {
		const notes: { key: string; text: string }[] = [];
		if (row.pausedUntil != null) {
			const ahead = Object.values(committedRows)
				.filter((other) => other.team === row.team && other.begin === today && other.track != null)
				.map((other) => nameOf(other.id));
			notes.push({
				key: `paused-${row.id}`,
				text: `${nameOf(row.id)} is in progress but pauses until ${short(row.pausedUntil)}: ${teamName(row.team)} runs ${tracksText(tracksOf(row.team))}, taken by ${ahead.length > 0 ? ahead.join(" and ") : "epics"} higher in its priority. Nothing on the board changes.`,
			});
		}
		if (row.blocked != null) {
			notes.push({
				key: `blocked-${row.id}`,
				text: `${nameOf(row.id)} is blocked, as ${blockedWhy(
					epics.find((epic) => epic.id === row.id),
					row,
					cardsOf[row.id] ?? [],
				)}. It gives up its track to the next epic in ${teamName(row.team)}'s priority, and its delivery is queued for the next track that frees after those epics${row.begin != null ? `, from ${short(row.begin)}` : ""}: the forecast assumes it is unblocked by then.`,
			});
		}
		if (row.pinIgnored && !row.done) {
			notes.push({
				key: `pin-${row.id}`,
				text: `${nameOf(row.id)} is pinned to track ${row.pin}, past the ${tracksText(tracksOf(row.team))} of ${teamName(row.team)}, so the plan places it itself.`,
			});
		}
		return notes;
	});

	if (!hydrated) {
		return (
			<section className="plan-page">
				<p className="empty plan-loading">Drawing the plan…</p>
			</section>
		);
	}

	function renderTrack(epic: Card) {
		const row = rows[epic.id];
		if (!row) return null;
		const active = drag?.id === epic.id && drag.mode !== "milestone";
		const pendingNow = pending.has(epic.id);
		const start = row.start;
		const target = row.target;
		const ends: number[] = [];
		const pieces: ReactNode[] = spans.map((one) => (
			<span
				key={`break-${one.id}`}
				className="plan-break"
				style={{ left: x(one.first), width: x(one.last + 1) - x(one.first) }}
				title={breakTitle(one)}
			/>
		));
		for (const span of blockedSpansOf(epic, cardsOf[epic.id] ?? [], today)) {
			pieces.push(
				<span
					key={`blocked-${span.from}`}
					className="plan-blocked-span"
					style={{ left: x(span.from), width: x(span.to + 1) - x(span.from) }}
					title={
						span.open
							? `Blocked since ${short(span.from)}, and still blocked today`
							: `Blocked from ${short(span.from)} to ${short(span.to)}`
					}
				/>,
			);
		}
		const scheduled = `${row.blocked != null ? `${blockedForecast(row)}, ` : ""}on track ${row.track} at ${figure(row.perWeek)} points a week${fallbackOf(row.team) ? `, a fallback: ${teamName(row.team)} has no done history, so it takes the board's overall average rather than a speed of its own` : ""}: ${runTitle(row)}`;
		if (row.refineStart != null && row.refineEnd != null) {
			const refinedTo = Math.min(row.refineEnd, today);
			if (refinedTo > row.refineStart) {
				pieces.push(
					<span
						key="refined"
						className="plan-refine"
						style={{ left: x(row.refineStart), width: x(refinedTo) - x(row.refineStart) }}
						title={
							row.refineForecast
								? `In refinement since ${short(row.refineStart)}`
								: `Refined from ${short(row.refineStart)} to ${short(row.refineEnd)}, when it reached Ready for Dev`
						}
					/>,
				);
			}
			const from = Math.max(row.refineStart, today);
			if (row.refineForecast && row.refineEnd > from) {
				pieces.push(
					<span
						key="refining"
						className="plan-refine forecast"
						style={{ left: x(from), width: x(row.refineEnd) - x(from) }}
						title={`${row.phase === "backlog" ? `Refinement forecast to start ${short(row.refineStart)}, as refinement has no limit, and` : "Refinement"} forecast to end ${short(row.refineEnd)}: ${refinementText(refinement)}`}
					/>,
				);
			}
			ends.push(row.refineEnd);
		}
		if (!row.refineForecast && row.refineEnd != null && (row.phase === "delivery" || row.phase === "done")) {
			const until = row.phase === "done" ? (row.doneDay ?? today) + 1 : today;
			if (until > row.refineEnd) {
				const delivered = progressOf(cardsOf[epic.id] ?? []);
				pieces.push(
					<span
						key="delivered"
						className="plan-run delivered"
						style={{ left: x(row.refineEnd), width: x(until) - x(row.refineEnd) }}
						title={`${row.phase === "done" ? "Delivered" : "Delivering"} from ${short(row.refineEnd)}${row.phase === "done" ? ` to ${short(until - 1)}` : " to today"}: ${delivered.done} of ${delivered.total} cards done, ${figure(delivered.donePoints)} pts of TR complexity - done work stays behind today and never moves`}
					/>,
				);
			}
		}
		if (row.pausedUntil != null) {
			pieces.push(
				<span
					key="paused"
					className="plan-paused"
					style={{ left: x(today), width: x(row.pausedUntil) - x(today) }}
					title={`Paused from today until ${short(row.pausedUntil)}, when a track of ${teamName(row.team)} frees`}
				/>,
			);
		}
		if (row.blocked != null) {
			pieces.push(
				<span
					key="blocked"
					className="plan-blocked"
					style={{ left: x(today) + ppd / 2 - 7 }}
					title={`Blocked, as ${blockedWhy(epic, row, cardsOf[epic.id] ?? [])} - ${blockedForecast(row)}`}
				>
					<Icon name="blocked" />
				</span>,
			);
			ends.push(today);
		}
		if (row.begin != null && row.projected != null && row.remaining.points > 0) {
			const left = x(row.begin);
			const length = x(row.projected + 1) - left;
			const solid = length * (row.remaining.complexity / row.remaining.points);
			if (row.remaining.complexity > 0) {
				pieces.push(
					<span
						key="run-tr"
						className="plan-run"
						style={{ left, width: solid }}
						title={`Scheduled from ${short(row.begin)} to ${short(row.projected)} ${scheduled}`}
					/>,
				);
			}
			if (row.remaining.fromEstimate > 0) {
				pieces.push(
					<span
						key="run-td"
						className="plan-run estimated"
						style={{ left: left + solid, width: length - solid }}
						title={`Scheduled from ${short(row.begin)} to ${short(row.projected)} ${scheduled}`}
					/>,
				);
			}
		}
		if (row.remaining.unsized > 0 && !row.done && row.begin != null) {
			const at = row.projected != null && row.remaining.points > 0 ? x(row.projected + 1) : x(row.begin);
			ends.push(row.projected ?? row.begin);
			pieces.push(
				<span key="unsized" className="plan-unsized" style={{ left: at + 2 }} title={runTitle(row)}>
					?
				</span>,
			);
		}
		if (start != null && target != null) {
			const left = x(Math.min(start, target));
			const right = x(Math.max(start, target) + 1);
			ends.push(Math.max(start, target));
			pieces.push(
				<span
					key="bar"
					className={`plan-bar${row.backwards ? " backwards" : ""}${row.done ? " done" : ""}`}
					style={{ left, width: Math.max(right - left, 6) }}
					title={
						row.backwards
							? `It started ${short(start)}, after its target of ${short(target)} - drag to move the target`
							: `Started ${short(start)}, target ${short(target)} - drag to move the target`
					}
					onPointerDown={(event) => beginDrag(event, { mode: "target", id: epic.id, start, target, anchor: null })}
				>
					<span
						className="plan-end target"
						aria-hidden="true"
						onPointerDown={(event) => beginDrag(event, { mode: "target", id: epic.id, start, target, anchor: null })}
					/>
				</span>,
			);
		} else if (target != null) {
			ends.push(target);
			pieces.push(
				<span
					key="target"
					className="plan-flag"
					style={{ left: x(target + 1) - 7 }}
					title={`Target ${short(target)}, not started yet - drag to move it`}
					onPointerDown={(event) => beginDrag(event, { mode: "target", id: epic.id, start, target, anchor: null })}
				>
					<Icon name="target" />
				</span>,
			);
		} else if (start != null) {
			ends.push(start);
			pieces.push(
				<span
					key="start"
					className="plan-flag start"
					style={{ left: x(start) - 1 }}
					title={`Started ${short(start)}, with no target - drag along the timeline to give it one`}
				>
					<span className="plan-start-tick" />
				</span>,
			);
		}
		const words: string[] = [];
		if (row.done) {
			if (row.doneDay != null) {
				ends.push(row.doneDay);
				pieces.push(
					<span key="done" className="plan-mark done" style={{ left: x(row.doneDay) + ppd / 2 - 7 }}>
						<Icon name="done" />
					</span>,
				);
				if (row.late > 0 && target != null) {
					pieces.push(
						<span
							key="late"
							className="plan-late"
							style={{ left: x(target + 1), width: x(row.doneDay + 1) - x(target + 1) }}
						/>,
					);
				}
			}
			words.push(row.doneDay != null ? `Done ${short(row.doneDay)}` : "Done");
			if (row.late > 0) words.push(lateText(row.late, true));
		} else if (row.projected != null) {
			ends.push(row.projected);
			pieces.push(
				<span
					key="projected"
					className="plan-mark projected"
					style={{ left: x(row.projected) + ppd / 2 - 7 }}
					title={`Projected to end ${short(row.projected)}${row.blocked != null ? `, ${blockedForecast(row)}` : ""}: ${runTitle(row)}`}
				>
					<Icon name="projected" />
				</span>,
			);
			words.push(
				row.remaining.open === 0
					? `All cards done ${short(row.projected)}`
					: `Projected ${short(row.projected)}${row.blocked != null ? " if unblocked" : ""}`,
			);
		} else if (row.remaining.points > 0 && tracksOf(row.team) === 0) {
			words.push(`Not scheduled - ${teamName(row.team)} has no tracks`);
		} else if (row.remaining.unsized > 0) {
			words.push("Unsized");
		} else if (row.remaining.open + row.remaining.done === 0) {
			words.push("No cards to project");
			if (target != null && target < today) words.push(`target passed ${short(target)}`);
		}
		if (!row.done && row.late > 0 && target != null) {
			const why =
				row.remaining.open === 0
					? `its last card was done ${row.late === 1 ? "1 day" : `${row.late} days`} after its target of ${short(target)}`
					: row.projected != null && row.projected > today
						? `projected to end ${short(row.projected)}, past its target of ${short(target)}`
						: `its target of ${short(target)} has passed with work still open`;
			ends.push(target + row.late);
			pieces.push(
				<span
					key="late"
					className="plan-late"
					style={{ left: x(target + 1), width: x(target + row.late + 1) - x(target + 1) }}
					title={`${lateText(row.late, false)}: ${why}`}
				/>,
			);
			words.push(lateText(row.late, false));
		}
		const empty = target == null;
		const reach = ends.length > 0 ? x(Math.max(...ends) + 1) + 10 : x(today) + 10;
		return (
			<div
				className={`plan-track${empty ? " empty" : ""}${active ? " dragging" : ""}${pendingNow ? " pending" : ""}`}
				style={{ width }}
				onPointerDown={
					empty && !row.done
						? (event) => beginDrag(event, { mode: "draw", id: epic.id, start, target: null, anchor: dayAt(event) })
						: undefined
				}
				title={empty && !row.done ? "Drag along the timeline to give it a target" : undefined}
			>
				{pieces}
				{words.length > 0 && (
					<span
						className={`plan-label${row.late > 0 ? " late" : ""}${row.done ? " done" : ""}${row.blocked != null ? " blocked" : ""}`}
						style={{ left: Math.min(reach, Math.max(0, width - 200)) }}
					>
						{row.late > 0 && <Icon name="late" />}
						{words.join(" · ")}
					</span>
				)}
				{active && drag && (
					<span className="plan-drag-tip" style={{ left: Math.min(Math.max(0, reach), Math.max(0, width - 200)) }}>
						{(() => {
							const next = moved(drag);
							return `Target ${next.target == null ? "none" : short(next.target)}`;
						})()}
					</span>
				)}
			</div>
		);
	}

	function renderRow(epic: Card) {
		const row = rows[epic.id];
		const progress = progressOf(cardsOf[epic.id] ?? []);
		const needed = row?.needed;
		const short_of = needed != null && row != null && needed > row.perWeek;
		return (
			<RowDrop
				key={epic.id}
				id={epic.id}
				className={`plan-row${openId === epic.id ? " open" : ""}${rowDragging === epic.id ? " lifted" : ""}`}
			>
				<div className="plan-left">
					<Handle id={epic.id} name={epic.name} />
					<div className="plan-who">
						<button
							type="button"
							className="plan-name"
							onClick={() => show(epic.id)}
							title={`${epic.id} · ${epic.status}`}
						>
							{epic.icon && <span className="record-icon">{epic.icon}</span>}
							{epic.name}
						</button>
						<span className="plan-meta">
							<StatusChip epic={epic} row={row} onPick={(value) => pickStatus(epic, value)} />
							{row?.blocked != null && (
								<span
									className="plan-points blocked"
									title={`Blocked, as ${blockedWhy(epic, row, cardsOf[epic.id] ?? [])} - ${blockedForecast(row)}`}
								>
									<Icon name="blocked" />
									Blocked
								</span>
							)}
							{row && !row.done && tracksOf(row.team) > 0 && (
								<TrackPick
									epic={epic}
									row={row}
									count={tracksOf(row.team)}
									onPick={(value) => pickTrack(epic, value)}
								/>
							)}
							{row && !row.done && row.remaining.tickets > 0 && <span className="plan-sr">{runTitle(row)}</span>}
							{row && !row.done && row.projected != null && row.remaining.points > 0 && fallbackOf(row.team) && (
								<span
									className="plan-points fallback"
									title={`Projected at ${figure(row.perWeek)} points a week a track, a fallback rather than a measured speed: ${teamName(row.team)} has no ticket with a TR complexity finished on the last ${AVERAGE_SPEED_DAYS} working days, so it takes the board's overall average`}
								>
									<Icon name="plan" />
									Fallback speed
								</span>
							)}
							{row && !row.done && row.remaining.open + row.remaining.done === 0 && (
								<span className="plan-points none" title="Give it cards to project when it ends">
									No cards
								</span>
							)}
							{needed != null && (
								<span
									className={`plan-needs${short_of ? " short" : ""}`}
									title={
										needed === Number.POSITIVE_INFINITY
											? "Its target has passed with points still left"
											: `Meeting its target takes ${figure(needed)} points a week of five working days, over the working days left before it and counting every epic ahead of it on its track, against ${figure(row?.perWeek ?? 0)} done a week on a track`
									}
								>
									{short_of && <Icon name="plan" />}
									{needed === Number.POSITIVE_INFINITY ? "Target passed" : `Needs ${figure(needed)}/wk`}
								</span>
							)}
							{progress.total > 0 && <ProgressMeter progress={progress} />}
						</span>
					</div>
				</div>
				{renderTrack(epic)}
				<div className="plan-notes">
					<div className="plan-dates">
						<span className="plan-started" title="Stamped the day it first left Backlog">
							{epic.start ? short(dayOf(epic.start) ?? today) : "In Backlog"}
						</span>
						<TextField
							type="date"
							label={`Target of ${epic.id}`}
							value={epic.target ?? ""}
							onCommit={(value) =>
								commitTarget(
									epic.id,
									dayOf(value),
									`Changed the target of ${epic.id} to ${value ? short(dayOf(value) ?? 0) : "nothing"}`,
								)
							}
						/>
					</div>
					<LearningCell
						id={epic.id}
						value={epic.learning ?? ""}
						onCommit={(value) =>
							apply(
								epic.id,
								{ learning: value || null },
								() => editCard(epic.id, "learning", value),
								`Changed the learning of ${epic.id}`,
							)
						}
					/>
					<CommentsCell epic={epic} onCount={() => router.refresh()} />
				</div>
			</RowDrop>
		);
	}

	const overlayStyle: CSSProperties = {
		width,
		...(prefs.scale === "weeks"
			? {
					backgroundImage: `repeating-linear-gradient(to right, var(--plan-grid) 0 1px, transparent 1px ${7 * ppd}px)`,
					backgroundPosition: `${x(mondayOf(view.first))}px 0`,
				}
			: {}),
	};

	const dragging = rowDragging ? epics.find((epic) => epic.id === rowDragging) : null;
	const levels: Record<string, number> = {};
	const reached = [Number.NEGATIVE_INFINITY, Number.NEGATIVE_INFINITY, Number.NEGATIVE_INFINITY];
	for (const milestone of [...milestones].sort((a, b) => (a.date ?? "").localeCompare(b.date ?? ""))) {
		const day = dayOf(milestone.date);
		if (day == null) continue;
		const at = x(day);
		const free = reached.findIndex((last) => at - last >= 130);
		const level = free >= 0 ? free : reached.indexOf(Math.min(...reached));
		levels[milestone.id] = level;
		reached[level] = at;
	}
	const milestoneDrag = drag?.mode === "milestone" ? drag : null;

	return (
		<section className={`plan-page${open ? " peeking" : ""}`}>
			<div className="plan-main">
				<header className="plan-head">
					<h1>Plan</h1>
					<div className="segmented" role="group" aria-label="Scale">
						{(["weeks", "months"] as const).map((scale) => (
							<button
								key={scale}
								type="button"
								className={prefs.scale === scale ? "on" : undefined}
								aria-pressed={prefs.scale === scale}
								onClick={() => changePrefs({ scale })}
							>
								{scale === "weeks" ? "Weeks" : "Months"}
							</button>
						))}
					</div>
					<button type="button" className="chip-toggle" onClick={toToday}>
						Today
					</button>
					<button
						type="button"
						className={`chip-toggle${prefs.grouped ? " on" : ""}`}
						aria-pressed={prefs.grouped}
						onClick={() => changePrefs({ grouped: !prefs.grouped })}
					>
						By project
					</button>
					<span className="spacer" />
					<button
						type="button"
						className={`chip-toggle${breaksOpen ? " on" : ""}`}
						aria-pressed={breaksOpen}
						onClick={() => {
							setEditing(null);
							setBreakError(null);
							setBreaksOpen(!breaksOpen);
						}}
					>
						Breaks{breaks.length > 0 ? ` · ${breaks.length}` : ""}
					</button>
					<button
						type="button"
						className="chip-toggle"
						onClick={() => {
							setBreaksOpen(false);
							setEditing({ id: null, name: "", date: dayText(today) });
						}}
					>
						+ Milestone
					</button>
				</header>
				<div className="stat-row plan-stats">
					<div title={rateTitle}>
						<span className="stat-label">Average speed</span>
						<span className="stat-value">
							{figure(rate.perWeek)}{" "}
							<span>
								pts a week ·{" "}
								{rate.source === "measured" ? "measured" : rate.source === "sprint" ? "sprint speed" : "default"}
							</span>
						</span>
						<span className="plan-speed-from">{speedFrom(rate)}</span>
					</div>
					<div title="How many epics you can run at once across the board, shared out between the projects by hand">
						<span className="stat-label">Tracks</span>
						<span className="stat-value plan-board-tracks">
							<span className="plan-tracks-step" role="group" aria-label="The board's tracks">
								<button
									type="button"
									className="quiet"
									disabled={boardCount <= Math.max(1, allocated)}
									aria-label="One track fewer for the board"
									title={
										boardCount <= allocated
											? "Every track is given to a project - take one from a project first"
											: "One track fewer for the board"
									}
									onClick={() => changeBoardTracks(boardCount - 1)}
								>
									−
								</button>
								<span className="plan-tracks-count">{boardCount}</span>
								<button
									type="button"
									className="quiet"
									aria-label="One track more for the board"
									title="One track more for the board, to give a project"
									onClick={() => changeBoardTracks(boardCount + 1)}
								>
									+
								</button>
							</span>
						</span>
						<span className="plan-speed-from">
							{allocated} given to projects
							{boardCount > allocated ? ` · ${boardCount - allocated} unallocated` : " · none unallocated"}
						</span>
					</div>
					<div title={`Refinement still to come is forecast at this: ${refinementText(refinement)}`}>
						<span className="stat-label">Refinement</span>
						<span className="stat-value">
							{refinement.days} <span>working days · {refinement.source === "measured" ? "measured" : "default"}</span>
						</span>
						<span className="plan-speed-from">
							{refinement.source === "measured"
								? `from ${refinement.epics} ${refinement.epics === 1 ? "epic" : "epics"}, Backlog to Ready for Dev`
								: "no epic refined yet"}
						</span>
					</div>
					<div title="Open tickets with neither a TR complexity nor a TD estimate, left out of every sum and date">
						<span className="stat-label">Unsized</span>
						<span className="stat-value">
							{unsized} <span>open {unsized === 1 ? "ticket" : "tickets"} left out</span>
						</span>
					</div>
					<div>
						<span className="stat-label">Points left</span>
						<span className="stat-value">{figure(pointsLeft)}</span>
					</div>
					<div className={lateCount > 0 ? "alert" : undefined}>
						<span className="stat-label">Plan ends</span>
						<span className="stat-value">
							{Number.isFinite(planEnd) ? short(planEnd) : "-"}{" "}
							<span>{lateCount > 0 ? `${lateCount} late` : "none late"}</span>
						</span>
					</div>
				</div>
				{notice && (
					<p className="notice error" role="alert">
						<span>{notice.text}</span>
						<button type="button" className="quiet" onClick={() => setNotice(null)}>
							Dismiss
						</button>
					</p>
				)}
				{homeless.length > 0 && (
					<p className="report-note plan-homeless">
						{homeless.length === 1 ? "This epic needs a project" : "These epics need a project"} before the plan can
						place {homeless.length === 1 ? "it" : "them"}:{" "}
						{homeless.map((epic, index) => (
							<span key={epic.id}>
								{index > 0 && ", "}
								<Link href={`/epics?open=${epic.id}`}>
									{epic.id} {epic.name}
								</Link>
							</span>
						))}
					</p>
				)}
				{trackNotes.length > 0 && (
					<ul className="report-note plan-track-notes">
						{trackNotes.map((note) => (
							<li key={note.key}>{note.text}</li>
						))}
					</ul>
				)}
				{(view.clippedBefore || view.clippedAfter) && (
					<p className="report-note plan-clipped">
						The timeline stops {view.clippedBefore ? "two years back" : ""}
						{view.clippedBefore && view.clippedAfter ? " and " : ""}
						{view.clippedAfter ? "five years ahead" : ""} - what lies past that is cut at the edge.
					</p>
				)}
				{breaksOpen && (
					<BreaksEditor
						breaks={breaks}
						busy={saving}
						error={breakError}
						onAdd={addBreakFrom}
						onRemove={removeBreakOf}
						onClose={() => setBreaksOpen(false)}
					/>
				)}
				{editing && (
					<MilestoneEditor
						editing={editing}
						busy={saving}
						onChange={setEditing}
						onSave={saveMilestone}
						onRemove={dropMilestone}
						onClose={() => setEditing(null)}
					/>
				)}
				<DndContext
					id={dndId}
					sensors={sensors}
					onDragStart={(event: DragStartEvent) => setRowDragging(String(event.active.id).slice(4))}
					onDragEnd={onRowDragEnd}
					onDragCancel={() => setRowDragging(null)}
				>
					<div className={`plan-scroll scale-${prefs.scale}`} ref={scroller}>
						<div className="plan-sheet" style={{ "--timeline": `${width}px` } as CSSProperties}>
							<div className="plan-header">
								<div className="plan-left plan-corner">
									<span>Epic</span>
									<span className="plan-corner-status">Status · track · speed needed</span>
								</div>
								<div className="plan-scale" style={{ width }}>
									<div className="plan-months">
										{months.map((month) => (
											<span key={month.day} style={{ left: x(month.day) }}>
												{month.label}
											</span>
										))}
									</div>
									{mondays.length > 0 && (
										<div className="plan-weeks">
											{mondays.map((monday) => (
												<span
													key={monday}
													style={{ left: x(monday), width: 7 * ppd }}
													title={`Week of ${long(monday)}`}
												>
													{new Date(monday * DAY).getUTCDate()}
												</span>
											))}
										</div>
									)}
									<div
										className="plan-lane"
										title="Double-click to add a milestone on that day"
										onDoubleClick={(event) => {
											const box = event.currentTarget.getBoundingClientRect();
											const day = view.first + Math.floor((event.clientX - box.left) / ppd);
											setEditing({ id: null, name: "", date: dayText(day) });
										}}
									>
										{milestones.map((milestone) => {
											const day = dayOf(milestone.date);
											if (day == null) return null;
											const at = milestoneDrag?.id === milestone.id ? day + milestoneDrag.delta : day;
											return (
												<button
													type="button"
													key={milestone.id}
													className={`plan-milestone${milestoneDrag?.id === milestone.id ? " dragging" : ""}`}
													style={{ left: x(at) + ppd / 2 - 6, top: 2 + 17 * (levels[milestone.id] ?? 0) }}
													title={`${milestone.name} · ${long(at)} - drag to move it, click to edit`}
													onPointerDown={(event) =>
														beginDrag(event, {
															mode: "milestone",
															id: milestone.id,
															start: day,
															target: null,
															anchor: null,
														})
													}
													onKeyDown={(event) => {
														if (event.key === "Enter" || event.key === " ") {
															event.preventDefault();
															setEditing({ id: milestone.id, name: milestone.name, date: milestone.date ?? "" });
														}
													}}
												>
													<Icon name="milestone" />
													<span>{milestone.name}</span>
												</button>
											);
										})}
									</div>
									{spans.map((one) => (
										<span
											key={one.id}
											className="plan-break-scale"
											style={{ left: x(one.first), width: x(one.last + 1) - x(one.first) }}
											title={breakTitle(one)}
										/>
									))}
									<span className="plan-today-label" style={{ left: x(today) + ppd / 2 }}>
										Today
									</span>
								</div>
								<div className="plan-notes plan-notes-head">
									<span>Start · Target</span>
									<span>Learning</span>
									<span>Comments</span>
								</div>
							</div>
							<div className="plan-body">
								<div className="plan-lines" style={overlayStyle} aria-hidden="true">
									{prefs.scale === "months" &&
										months.map((month) => (
											<span key={month.day} className="plan-month-line" style={{ left: x(month.day) }} />
										))}
									{milestones.map((milestone) => {
										const day = dayOf(milestone.date);
										if (day == null) return null;
										const at = milestoneDrag?.id === milestone.id ? day + milestoneDrag.delta : day;
										return (
											<span key={milestone.id} className="plan-milestone-line" style={{ left: x(at) + ppd / 2 }} />
										);
									})}
									{spans.map((one) => (
										<span
											key={one.id}
											className="plan-break-line"
											style={{ left: x(one.first), width: x(one.last + 1) - x(one.first) }}
										/>
									))}
									<span className="plan-today" style={{ left: x(today) + ppd / 2 }} />
								</div>
								{epics.length === 0 && (
									<p className="empty plan-empty">
										No epic is on the board yet - create one on the <Link href="/epics">Epics</Link> page and it shows
										here.
									</p>
								)}
								{groups.map((group) => (
									<div key={group.id} className="plan-group">
										{prefs.grouped && (
											<div className="plan-group-head">
												<span className="plan-left">
													{group.icon && <span className="record-icon">{group.icon}</span>}
													{group.name}
													<span className="count">{group.epics.length}</span>
													{group.team && (
														<TracksControl
															name={group.name}
															count={tracksOf(group.team)}
															speed={speeds.teams[group.team] ?? speeds.overall}
															onChange={(count) => changeTracks(group.team ?? "", count)}
														/>
													)}
												</span>
											</div>
										)}
										{group.epics.map((epic) => renderRow(shown.find((one) => one.id === epic.id) ?? epic))}
									</div>
								))}
							</div>
						</div>
					</div>
					<DragOverlay dropAnimation={null}>
						{dragging && <div className="plan-row-ghost">{dragging.name}</div>}
					</DragOverlay>
				</DndContext>
				<footer className={`plan-legend${legendOpen ? " open" : ""}`} aria-label="Legend">
					<button
						type="button"
						className="quiet plan-legend-toggle"
						aria-expanded={legendOpen}
						onClick={() => setLegendOpen(!legendOpen)}
					>
						{legendOpen ? "Hide the legend" : "Legend"}
					</button>
					<span>
						<span className="legend-bar" /> Start to target
					</span>
					<span>
						<span className="legend-refine" /> Refinement done
					</span>
					<span>
						<span className="legend-refine forecast" /> Refinement forecast
					</span>
					<span>
						<span className="legend-run delivered" /> Delivered so far
					</span>
					<span>
						<span className="legend-run" /> Scheduled on TR complexity
					</span>
					<span>
						<span className="legend-run estimated" /> Scheduled on TD estimates
					</span>
					<span>
						<span className="legend-unsized">?</span> Unsized tickets, left out
					</span>
					<span>
						<span className="legend-paused" /> Paused until a track frees
					</span>
					<span>
						<span className="legend-blocked">
							<Icon name="blocked" />
						</span>{" "}
						Blocked, forecast after the epics that took its track
					</span>
					<span>
						<Icon name="projected" /> Projected end
					</span>
					<span>
						<Icon name="late" /> Days late past the target
					</span>
					<span>
						<Icon name="done" /> Delivered
					</span>
					<span>
						<span className="legend-today" /> Today
					</span>
					<span>
						<span className="legend-break" /> Break, nothing forecast
					</span>
					<span>
						<Icon name="milestone" /> Milestone
					</span>
					<span className="legend-gap" />
					{["On track", "At risk - plan in place", "At risk - no plan", DONE, ""].map((value) => (
						<span key={value || "none"} className={`tone-${STATUSES[value].tone}`}>
							<Icon name={STATUSES[value].icon} /> {STATUSES[value].label}
						</span>
					))}
				</footer>
			</div>
			{open && (
				<PlanPanel
					epic={open}
					cards={cards.filter((card) => card.epic === open.id)}
					lists={lists}
					handlers={handlersFor(open)}
					notice={notice?.id === open.id ? notice : null}
					onDismiss={() => setNotice(null)}
					onClose={() => show(null)}
					onSaved={(saved, spanned, label) => {
						setEpics((current) => current.map((epic) => (epic.id === saved.id ? saved : epic)));
						setToast(undoable(saved.id, spanned, label ?? `Changed the content of ${saved.id}`));
						router.refresh();
					}}
				/>
			)}
			{finishing && (
				<EpicDoneDialog
					finishing={finishing}
					busy={saving}
					onDeprioritise={() => finish(finishing)}
					onAnyway={() => {
						const epic = epics.find((one) => one.id === finishing.id);
						setFinishing(null);
						if (epic) moveEpic(epic, "Epic Done", true);
					}}
					onCancel={() => setFinishing(null)}
				/>
			)}
			<UndoToast toast={toast} busy={undoing} onUndo={undo} onDismiss={() => setToast(null)} />
		</section>
	);
}
