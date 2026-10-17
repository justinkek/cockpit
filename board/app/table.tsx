"use client";

import type { ReactNode } from "react";
import type { Lists } from "@/app/fields";
import { lastMoved } from "@/app/view";
import { ProgressMeter } from "@/app/progress";
import { flowOf, type Progress, progressShare, span } from "@/lib/metrics";
import {
	boardColumns,
	bounces,
	type Card,
	dueState,
	type Kind,
	kindName,
	MODEL_STAGES,
	phaseOf,
	SPLIT_ABOVE,
} from "@/lib/shared";

type Value = string | number | null;

type Context = {
	epics: Record<string, string>;
	epicProjects: Record<string, string | null | undefined>;
	sprints: Record<string, string>;
	projects: Record<string, string>;
	columns: string[];
	progress: Record<string, Progress>;
};

type Column = {
	key: string;
	label: string;
	kinds?: Kind[];
	numeric?: boolean;
	wide?: boolean;
	value: (entity: Card, context: Context) => Value;
	cell?: (entity: Card, context: Context) => ReactNode;
};

export function LabelPills({ labels }: { labels?: string[] | null }) {
	if (!labels || labels.length === 0) return null;
	return (
		<>
			{labels.map((label) => (
				<span key={label} className="pill label">
					{label}
				</span>
			))}
		</>
	);
}

function projectOf(entity: Card, context: Context) {
	const id = entity.project ?? (entity.epic ? context.epicProjects[entity.epic] : null);
	return id ? (context.projects[id] ?? id) : null;
}

function shortDate(stamp: string | null | undefined) {
	if (!stamp) return null;
	const date = new Date(stamp);
	if (Number.isNaN(date.getTime())) return stamp;
	const thisYear = date.getFullYear() === new Date().getFullYear();
	return date.toLocaleDateString(undefined, { day: "numeric", month: "short", year: thisYear ? undefined : "numeric" });
}

function Stamp({ stamp }: { stamp: string | null | undefined }) {
	if (!stamp) return null;
	const date = new Date(stamp);
	return (
		<time dateTime={stamp} title={Number.isNaN(date.getTime()) ? stamp : date.toLocaleString()}>
			{shortDate(stamp)}
		</time>
	);
}

function reworkOf(entity: Card) {
	return bounces(entity).reduce((sum, [, count]) => sum + count, 0);
}

const COLUMNS: Column[] = [
	{ key: "id", label: "ID", value: (entity) => Number(entity.id.split("-").at(-1)) },
	{ key: "name", label: "Name", value: (entity) => entity.name },
	{
		key: "status",
		label: "Status",
		value: (entity, context) => {
			const index = context.columns.indexOf(entity.status);
			return index < 0 ? context.columns.length : index;
		},
		cell: (entity) => (
			<span className="cell-status">
				<span className={`dot phase-${phaseOf(entity.status)}`} aria-hidden="true" />
				{entity.status}
			</span>
		),
	},
	{
		key: "type",
		label: "Type",
		kinds: ["card"],
		value: (entity) => entity.type ?? null,
		cell: (entity) => entity.type && <span className={`type type-${entity.type.toLowerCase()}`}>{entity.type}</span>,
	},
	{
		key: "epic",
		label: "Epic",
		kinds: ["card"],
		wide: true,
		value: (entity, context) => (entity.epic ? (context.epics[entity.epic] ?? entity.epic) : null),
	},
	{ key: "project", label: "Project", value: projectOf },
	{
		key: "urgent",
		label: "Urgent",
		kinds: ["card"],
		value: (entity) => (entity.urgent ? 1 : null),
		cell: (entity) => entity.urgent && <span className="pill urgent">Urgent</span>,
	},
	{
		key: "labels",
		label: "Labels",
		wide: true,
		value: (entity) => (entity.labels ?? []).join(", ") || null,
		cell: (entity) => <LabelPills labels={entity.labels} />,
	},
	{
		key: "progress",
		label: "Progress",
		kinds: ["epic"],
		numeric: true,
		value: (entity, context) => {
			const progress = context.progress[entity.id];
			return progress && progress.total > 0 ? progressShare(progress) : null;
		},
		cell: (entity, context) => {
			const progress = context.progress[entity.id];
			return progress && <ProgressMeter progress={progress} />;
		},
	},
	{
		key: "sprint",
		label: "Sprint",
		kinds: ["card"],
		value: (entity, context) => (entity.sprint ? (context.sprints[entity.sprint] ?? entity.sprint) : null),
	},
	{
		key: "complexity",
		label: "Points",
		kinds: ["card"],
		numeric: true,
		value: (entity) => entity.complexity ?? null,
		cell: (entity) =>
			entity.complexity != null && (
				<span className={entity.complexity > SPLIT_ABOVE ? "split" : undefined}>{entity.complexity}</span>
			),
	},
	{
		key: "timebox",
		label: "Timebox",
		kinds: ["card"],
		numeric: true,
		value: (entity) => entity.timebox_mins ?? null,
		cell: (entity) => entity.timebox_mins != null && `${entity.timebox_mins}m`,
	},
	{
		key: "blocked",
		label: "Blocked",
		kinds: ["card"],
		wide: true,
		value: (entity) => entity.blocked ?? null,
		cell: (entity) => entity.blocked && <span className="cell-blocked">{entity.blocked}</span>,
	},
	{
		key: "dependent_on",
		label: "Waits on",
		kinds: ["card"],
		value: (entity) => (entity.dependent_on ?? []).join(", ") || null,
	},
	{ key: "session", label: "Claimed by", value: (entity) => entity.session ?? null },
	{
		key: "due",
		label: "Due",
		kinds: ["card"],
		value: (entity) => entity.due ?? null,
		cell: (entity) => {
			const due = dueState(entity);
			return (
				due && (
					<span className={`due-${due.tone}`} title={due.title}>
						{shortDate(entity.due)}
						{due.held && " · target"}
					</span>
				)
			);
		},
	},
	{ key: "prs", label: "PRs", kinds: ["card"], wide: true, value: (entity) => entity.prs ?? null },
	{
		key: "cost",
		label: "Cost",
		kinds: ["card"],
		numeric: true,
		value: (entity) => entity.cost_usd ?? null,
		cell: (entity) => entity.cost_usd != null && `$${entity.cost_usd.toFixed(2)}`,
	},
	{
		key: "tokens",
		label: "Tokens",
		kinds: ["card"],
		numeric: true,
		value: (entity) => entity.tokens_k ?? null,
		cell: (entity) => entity.tokens_k != null && `${entity.tokens_k}k`,
	},
	{ key: "comments", label: "Threads", numeric: true, value: (entity) => entity.comments || null },
	{
		key: "rework",
		label: "Back from",
		kinds: ["card"],
		numeric: true,
		value: (entity) => reworkOf(entity) || null,
		cell: (entity) =>
			bounces(entity)
				.map(([gate, count]) => `${gate} ${count}`)
				.join(", "),
	},
	...MODEL_STAGES.map((stage): Column => ({
		key: `model:${stage}`,
		label: `${stage} model`,
		kinds: ["card"],
		value: (entity) => entity.models?.[stage] ?? null,
	})),
	{
		key: "days",
		label: "Days in column",
		numeric: true,
		value: (entity) => entity.days_in_column ?? null,
	},
	{
		key: "lead",
		label: "Lead time",
		numeric: true,
		value: (entity) => flowOf(entity).lead,
		cell: (entity) => {
			const lead = flowOf(entity).lead;
			return lead != null && span(lead);
		},
	},
	{
		key: "cycle",
		label: "Cycle time",
		numeric: true,
		value: (entity) => flowOf(entity).cycle,
		cell: (entity) => {
			const cycle = flowOf(entity).cycle;
			return cycle != null && <span suppressHydrationWarning>{span(cycle)}</span>;
		},
	},
	{
		key: "created",
		label: "Created",
		value: (entity) => entity.created,
		cell: (entity) => <Stamp stamp={entity.created} />,
	},
	{
		key: "moved",
		label: "Last moved",
		value: (entity) => lastMoved(entity),
		cell: (entity) => <Stamp stamp={lastMoved(entity)} />,
	},
];

function dateColumn(column: string): Column {
	return {
		key: `date:${column}`,
		label: column,
		value: (entity) => entity.dates?.[column] ?? null,
		cell: (entity) => <Stamp stamp={entity.dates?.[column]} />,
	};
}

export function tableColumns(kind: Kind, entities: Card[]) {
	const dated = new Set(entities.flatMap((entity) => Object.keys(entity.dates ?? {})));
	const ordered = boardColumns(kind).filter((column) => dated.has(column));
	const extra = [...dated].filter((column) => !ordered.includes(column)).sort();
	return [
		...COLUMNS.filter((column) => !column.kinds || column.kinds.includes(kind)),
		...[...ordered, ...extra].map(dateColumn),
	];
}

export function contextOf(kind: Kind, lists: Lists, progress: Record<string, Progress> = {}): Context {
	return {
		epics: Object.fromEntries(lists.epics.map((epic) => [epic.id, epic.name])),
		epicProjects: Object.fromEntries(lists.epics.map((epic) => [epic.id, epic.project])),
		sprints: Object.fromEntries(lists.sprints.map((sprint) => [sprint.id, sprint.name])),
		projects: Object.fromEntries(lists.projects.map((project) => [project.id, project.name])),
		columns: boardColumns(kind),
		progress,
	};
}

export type TableSort = { key: string; descending: boolean } | null;

export function parseTableSort(text: string): TableSort {
	if (!text) return null;
	const [key, direction] = text.split("|");
	return { key, descending: direction === "desc" };
}

export function nextTableSort(current: TableSort, key: string): string {
	if (current?.key !== key) return `${key}|asc`;
	return current.descending ? "" : `${key}|desc`;
}

function compare(a: Value, b: Value) {
	if (typeof a === "number" && typeof b === "number") return a - b;
	return String(a).localeCompare(String(b), undefined, { numeric: true });
}

export function sortTable(entities: Card[], columns: Column[], context: Context, sort: TableSort) {
	const column = sort && columns.find((candidate) => candidate.key === sort.key);
	if (!sort || !column) return entities;
	const keyed = entities.map((entity) => ({ entity, value: column.value(entity, context) }));
	keyed.sort((a, b) => {
		if (a.value == null || a.value === "") return b.value == null || b.value === "" ? 0 : 1;
		if (b.value == null || b.value === "") return -1;
		const order = compare(a.value, b.value);
		return sort.descending ? -order : order;
	});
	return keyed.map(({ entity }) => entity);
}

export function tableOrder(
	kind: Kind,
	entities: Card[],
	lists: Lists,
	text: string,
	progress: Record<string, Progress> = {},
) {
	return sortTable(entities, tableColumns(kind, entities), contextOf(kind, lists, progress), parseTableSort(text));
}

function Header({ column, sort, onSort }: { column: Column; sort: TableSort; onSort: (key: string) => void }) {
	const on = sort?.key === column.key;
	return (
		<th
			scope="col"
			className={column.numeric ? "numeric" : undefined}
			aria-sort={on ? (sort.descending ? "descending" : "ascending") : undefined}
		>
			<button type="button" className={on ? "on" : undefined} onClick={() => onSort(column.key)}>
				{column.label}
				<span className="sort-mark" aria-hidden="true">
					{on ? (sort.descending ? "↓" : "↑") : ""}
				</span>
			</button>
		</th>
	);
}

export function Table({
	kind,
	entities,
	columns,
	context,
	sort,
	onSort,
	pending,
	focusedId,
	selected,
	onOpen,
	footer,
}: {
	kind: Kind;
	entities: Card[];
	columns: Column[];
	context: Context;
	sort: TableSort;
	onSort: (key: string) => void;
	pending: Set<string>;
	focusedId: string | null;
	selected: Set<string>;
	onOpen: (id: string, toggle: boolean) => void;
	footer?: ReactNode;
}) {
	return (
		<div className="table-wrap">
			<table className="entities">
				<thead>
					<tr>
						{columns.map((column) => (
							<Header key={column.key} column={column} sort={sort} onSort={onSort} />
						))}
					</tr>
				</thead>
				<tbody>
					{entities.map((entity) => (
						<tr
							key={entity.id}
							className={
								[
									pending.has(entity.id) && "pending",
									focusedId === entity.id && "focused",
									selected.has(entity.id) && "selected",
								]
									.filter(Boolean)
									.join(" ") || undefined
							}
							onClick={(event) => {
								if ((event.target as HTMLElement).closest("button")) return;
								onOpen(entity.id, event.shiftKey || event.metaKey || event.ctrlKey);
							}}
						>
							<th scope="row">
								<button
									type="button"
									className="ident"
									data-card={entity.id}
									aria-pressed={selected.has(entity.id) || undefined}
									onClick={(event) => onOpen(entity.id, event.shiftKey || event.metaKey || event.ctrlKey)}
								>
									{entity.id}
								</button>
							</th>
							<td className="cell-name" title={entity.name}>
								{entity.icon && <span className="entity-icon">{entity.icon}</span>}
								{entity.name}
							</td>
							{columns.slice(2).map((column) => {
								const shown = column.cell ? column.cell(entity, context) : column.value(entity, context);
								const text = column.value(entity, context);
								return (
									<td
										key={column.key}
										className={
											[column.numeric && "numeric", column.wide && "wide"].filter(Boolean).join(" ") || undefined
										}
										title={column.wide && typeof text === "string" ? text : undefined}
									>
										{shown}
									</td>
								);
							})}
						</tr>
					))}
				</tbody>
			</table>
			{entities.length === 0 && <p className="table-empty">No {kindName(kind)} matches the view and the filters.</p>}
			{footer}
		</div>
	);
}
