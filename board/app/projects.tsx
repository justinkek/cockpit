"use client";

import {
	DndContext,
	type DragEndEvent,
	DragOverlay,
	type DragStartEvent,
	KeyboardSensor,
	PointerSensor,
	TouchSensor,
	useDraggable,
	useDroppable,
	useSensor,
	useSensors,
} from "@dnd-kit/core";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useId, useMemo, useState, useTransition } from "react";
import { closeProject, editCard, undoChange } from "@/app/actions";
import { type Notice, NoticeBar } from "@/app/board";
import { confirmDiscard } from "@/app/content";
import { type Closing, ProjectDoneDialog } from "@/app/epic-done";
import { NewOther } from "@/app/new-entity";
import { EntityOverlay, useOpenEntity } from "@/app/entity-overlay";
import { type Undoable, UndoToast, undoable } from "@/app/toast";

export type ProjectEntry = {
	id: string;
	name: string;
	key?: string | null;
	icon?: string | null;
	status: string;
	priority?: number | null;
	tracks?: number | null;
	epics: number;
	openEpics: number;
	open: number;
	done: number;
};

type Layout = "board" | "list";

const LAYOUTS: [Layout, string][] = [
	["board", "Board"],
	["list", "List"],
];

const STORAGE_KEY = "cockpit-projects-layout";

const COLUMNS = ["Not started", "In progress", "Done"];

const LIST_ORDER = ["In progress", "Not started", "Done"];

const PHASES: Record<string, string> = { "Not started": "idle", "In progress": "dev", Done: "done" };

function plural(count: number, one: string) {
	return `${count} ${one}${count === 1 ? "" : "s"}`;
}

function byPriority(a: ProjectEntry, b: ProjectEntry) {
	return (
		(a.priority ?? Number.POSITIVE_INFINITY) - (b.priority ?? Number.POSITIVE_INFINITY) || a.name.localeCompare(b.name)
	);
}

function loadLayout(): Layout | null {
	try {
		const saved = window.localStorage.getItem(STORAGE_KEY);
		return saved === "board" || saved === "list" ? saved : null;
	} catch {
		return null;
	}
}

function saveLayout(layout: Layout) {
	try {
		window.localStorage.setItem(STORAGE_KEY, layout);
	} catch {}
}

function Dot({ status }: { status: string }) {
	return <span className={`dot phase-${PHASES[status] ?? "idle"}`} aria-hidden="true" />;
}

function shareText(project: ProjectEntry) {
	if (project.tracks == null) return null;
	const share = plural(project.tracks, "track");
	return project.status === "Done" ? `${share}, not counted while done` : share;
}

function ProjectBody({ project }: { project: ProjectEntry }) {
	const share = shareText(project);
	return (
		<>
			<span className="card-top">
				<span className="ident">{project.id}</span>
				{project.priority != null && <span className="pill">P{project.priority}</span>}
			</span>
			<span className="name">
				{project.icon && <span className="entity-icon">{project.icon}</span>}
				{project.name.trim() || "(untitled)"}
			</span>
			<span className="meta">
				{share && (
					<span className="pill" title={`Its share of the board's tracks: ${share}`}>
						{share}
					</span>
				)}
				<span className="pill" title={`${plural(project.epics, "epic")} in all`}>
					{plural(project.openEpics, "open epic")}
				</span>
				<span className="pill" title={`${project.open} open, ${project.done} done`}>
					{project.open} open · {project.done} done
				</span>
			</span>
		</>
	);
}

function ProjectCard({
	project,
	pending,
	onOpen,
}: {
	project: ProjectEntry;
	pending: boolean;
	onOpen: (id: string) => void;
}) {
	const { attributes, listeners, setNodeRef, isDragging } = useDraggable({ id: project.id });
	return (
		<li ref={setNodeRef} className={isDragging ? "dragging" : undefined}>
			<button
				type="button"
				{...listeners}
				{...attributes}
				data-card={project.id}
				className={`card${pending ? " pending" : ""}`}
				onClick={() => onOpen(project.id)}
			>
				<ProjectBody project={project} />
			</button>
		</li>
	);
}

function ProjectLane({
	status,
	projects,
	pending,
	onOpen,
}: {
	status: string;
	projects: ProjectEntry[];
	pending: Set<string>;
	onOpen: (id: string) => void;
}) {
	const { setNodeRef, isOver } = useDroppable({ id: status });
	return (
		<section ref={setNodeRef} className={`lane${isOver ? " over" : ""}`}>
			<div className="lane-head">
				<Dot status={status} />
				<span className="lane-name">{status}</span>
				<span className="count">{projects.length}</span>
			</div>
			<ul>
				{projects.map((project) => (
					<ProjectCard key={project.id} project={project} pending={pending.has(project.id)} onOpen={onOpen} />
				))}
			</ul>
		</section>
	);
}

function matching(projects: ProjectEntry[], query: string) {
	const words = query.trim().toLowerCase();
	if (!words) return projects;
	return projects.filter((project) =>
		[project.id, project.name, project.key ?? ""].some((text) => text.toLowerCase().includes(words)),
	);
}

function ProjectList({ projects, onOpen }: { projects: ProjectEntry[]; onOpen: (id: string) => void }) {
	const groups = [
		...LIST_ORDER,
		...new Set(projects.map((project) => project.status).filter((status) => !LIST_ORDER.includes(status))),
	]
		.map((status) => ({ status, projects: projects.filter((project) => project.status === status).sort(byPriority) }))
		.filter((group) => group.projects.length > 0);
	return groups.map((group) => (
		<div key={group.status} className="report-card">
			<h2>
				<Dot status={group.status} />
				{group.status || "No status"} <span className="count">{group.projects.length}</span>
			</h2>
			<ul className="entity-list">
				{group.projects.map((project) => (
					<li key={project.id}>
						<span className="ident">{project.id}</span>
						<Link
							href={`/card/${project.id}`}
							className="report-name"
							onClick={(event) => {
								if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
								event.preventDefault();
								onOpen(project.id);
							}}
						>
							{project.icon && <span className="entity-icon">{project.icon}</span>}
							{project.name.trim() || "(untitled)"}
						</Link>
						<span className="entity-meta">
							{project.priority != null && <span className="pill">P{project.priority}</span>}
							<span title={`${project.open} open, ${project.done} done`}>
								{plural(project.epics, "epic")} · {project.open} open · {project.done} done
							</span>
						</span>
					</li>
				))}
			</ul>
		</div>
	));
}

export function Projects({ initial, error }: { initial: ProjectEntry[]; error?: string }) {
	const router = useRouter();
	const [projects, setProjects] = useState(initial);
	const [layout, setLayout] = useState<Layout>("board");
	const [loaded, setLoaded] = useState(false);
	const [dragging, setDragging] = useState<ProjectEntry | null>(null);
	const [pending, setPending] = useState<Set<string>>(new Set());
	const [notice, setNotice] = useState<Notice>(null);
	const [toast, setToast] = useState<Undoable | null>(null);
	const [undoing, setUndoing] = useState(false);
	const [closing, setClosing] = useState<Closing | null>(null);
	const [query, setQuery] = useState("");
	const [openId, openEntity] = useOpenEntity();
	const [, startTransition] = useTransition();
	const dndId = useId();

	useEffect(() => setProjects(initial), [initial]);

	useEffect(() => {
		const saved = loadLayout();
		if (saved) setLayout(saved);
		setLoaded(true);
	}, []);

	useEffect(() => {
		if (loaded) saveLayout(layout);
	}, [layout, loaded]);

	const sensors = useSensors(
		useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
		useSensor(TouchSensor, { activationConstraint: { delay: 220, tolerance: 6 } }),
		useSensor(KeyboardSensor),
	);

	const shown = useMemo(() => matching(projects, query), [projects, query]);

	const siblings = useMemo(() => {
		const opened = projects.find((project) => project.id === openId);
		if (!opened) return undefined;
		return {
			label: opened.status,
			entities: shown.filter((project) => project.status === opened.status).sort(byPriority),
		};
	}, [projects, shown, openId]);

	function show(id: string | null) {
		if (id !== openId && !confirmDiscard()) return;
		openEntity(id);
	}

	const columns = useMemo(
		() => [...COLUMNS, ...new Set(projects.map((project) => project.status).filter((status) => !COLUMNS.includes(status)))],
		[projects],
	);

	function markPending(id: string, on: boolean) {
		setPending((current) => {
			const next = new Set(current);
			if (on) next.add(id);
			else next.delete(id);
			return next;
		});
	}

	function move(id: string, status: string, checked = false) {
		const before = projects.find((project) => project.id === id);
		if (!before || before.status === status) return;
		setNotice(null);
		setToast(null);
		if (!checked && status === "Done" && (before.openEpics > 0 || before.open > 0)) {
			setClosing({ id, name: before.name, epics: before.openEpics, tickets: before.open });
			return;
		}
		setProjects((current) => current.map((project) => (project.id === id ? { ...project, status } : project)));
		markPending(id, true);
		startTransition(async () => {
			const result = await editCard(id, "status", status);
			markPending(id, false);
			if (result.error) {
				setProjects((current) => current.map((project) => (project.id === id ? before : project)));
				setNotice({ id, text: `${id}: ${result.error}` });
				return;
			}
			setToast(undoable(id, result.undo, `Moved ${id} to ${status}`));
			router.refresh();
		});
	}

	function close(shown: Closing) {
		const before = projects.find((project) => project.id === shown.id);
		if (!before) return;
		setProjects((current) =>
			current.map((project) =>
				project.id === shown.id ? { ...project, status: "Done", openEpics: 0, open: 0 } : project,
			),
		);
		markPending(shown.id, true);
		startTransition(async () => {
			const result = await closeProject(shown.id);
			markPending(shown.id, false);
			setClosing(null);
			if (result.error) {
				setProjects((current) => current.map((project) => (project.id === shown.id ? before : project)));
				setNotice({ id: shown.id, text: `${shown.id}: ${result.error}` });
				return;
			}
			const toast = undoable(shown.id, result.undo, `Closed ${shown.id} and everything open in it`);
			toast?.changes.push(...(result.closed ?? []));
			setToast(toast);
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
				const fresh = result.entity;
				if (fresh)
					setProjects((current) =>
						current.map((project) => (project.id === change.id ? { ...project, status: fresh.status } : project)),
					);
			}
			setUndoing(false);
			setToast((current) => (current?.key === shown.key ? null : current));
			if (failures.length > 0) setNotice({ id: "", text: `Could not undo: ${failures.join("; ")}` });
			router.refresh();
		});
	}

	function onDragStart(event: DragStartEvent) {
		setDragging(projects.find((project) => project.id === String(event.active.id)) ?? null);
	}

	function onDragEnd(event: DragEndEvent) {
		setDragging(null);
		if (event.over) move(String(event.active.id), String(event.over.id));
	}

	return (
		<section className="report projects">
			<header className="report-head">
				<h1>Projects</h1>
				<span className="count">{projects.length}</span>
				<span className="spacer" />
				<input
					type="search"
					className="search"
					placeholder="Search"
					aria-label="Search the projects"
					value={query}
					onChange={(event) => setQuery(event.target.value)}
				/>
				<div className="segmented" role="group" aria-label="Layout">
					{LAYOUTS.map(([choice, label]) => (
						<button
							key={choice}
							type="button"
							className={layout === choice ? "on" : undefined}
							aria-pressed={layout === choice}
							onClick={() => setLayout(choice)}
						>
							{label}
						</button>
					))}
				</div>
				<NewOther kind="project" />
			</header>
			{error && (
				<p className="notice error" role="alert">
					{error}
				</p>
			)}
			<NoticeBar notice={notice} onDismiss={() => setNotice(null)} />
			{projects.length === 0 && <p className="empty">No project is on the board yet.</p>}
			{projects.length > 0 && shown.length === 0 && <p className="empty">No project matches {query.trim()}.</p>}
			{shown.length > 0 && layout === "list" && <ProjectList projects={shown} onOpen={show} />}
			{shown.length > 0 && layout === "board" && (
				<DndContext
					id={dndId}
					sensors={sensors}
					onDragStart={onDragStart}
					onDragEnd={onDragEnd}
					onDragCancel={() => setDragging(null)}
				>
					<div className="lanes project-lanes">
						{columns.map((status) => (
							<ProjectLane
								key={status}
								status={status}
								projects={shown.filter((project) => project.status === status).sort(byPriority)}
								pending={pending}
								onOpen={show}
							/>
						))}
					</div>
					<DragOverlay dropAnimation={null}>
						{dragging && (
							<div className="card drag-overlay">
								<ProjectBody project={dragging} />
							</div>
						)}
					</DragOverlay>
				</DndContext>
			)}
			{closing && (
				<ProjectDoneDialog
					closing={closing}
					busy={pending.has(closing.id)}
					onClose={() => close(closing)}
					onAnyway={() => {
						setClosing(null);
						move(closing.id, "Done", true);
					}}
					onCancel={() => setClosing(null)}
				/>
			)}
			<UndoToast toast={toast} busy={undoing} onUndo={undo} onDismiss={() => setToast(null)} />
			{openId && (
				<EntityOverlay
					id={openId}
					siblings={siblings}
					onOpen={(id) => show(id)}
					onClose={() => show(null)}
					onChanged={() => router.refresh()}
				/>
			)}
		</section>
	);
}
