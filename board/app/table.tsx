"use client";

import type { ReactNode } from "react";
import type { Lists } from "@/app/fields";
import { lastMoved } from "@/app/view";
import {
	boardColumns,
	bounces,
	type Card,
	dueState,
	type Kind,
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
};

type Column = {
	key: string;
	label: string;
	kinds?: Kind[];
	numeric?: boolean;
	wide?: boolean;
	value: (record: Card, context: Context) => Value;
	cell?: (record: Card, context: Context) => ReactNode;
};

function projectOf(record: Card, context: Context) {
	const id = record.project ?? (record.epic ? context.epicProjects[record.epic] : null);
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

function reworkOf(record: Card) {
	return bounces(record).reduce((sum, [, count]) => sum + count, 0);
}

const COLUMNS: Column[] = [
	{ key: "id", label: "ID", value: (record) => Number(record.id.split("-").at(-1)) },
	{ key: "name", label: "Name", value: (record) => record.name },
	{
		key: "status",
		label: "Status",
		value: (record, context) => {
			const index = context.columns.indexOf(record.status);
			return index < 0 ? context.columns.length : index;
		},
		cell: (record) => (
			<span className="cell-status">
				<span className={`dot phase-${phaseOf(record.status)}`} aria-hidden="true" />
				{record.status}
			</span>
		),
	},
	{
		key: "type",
		label: "Type",
		kinds: ["card"],
		value: (record) => record.type ?? null,
		cell: (record) => record.type && <span className={`type type-${record.type.toLowerCase()}`}>{record.type}</span>,
	},
	{
		key: "epic",
		label: "Epic",
		kinds: ["card"],
		wide: true,
		value: (record, context) => (record.epic ? (context.epics[record.epic] ?? record.epic) : null),
	},
	{ key: "project", label: "Project", value: projectOf },
	{
		key: "sprint",
		label: "Sprint",
		kinds: ["card"],
		value: (record, context) => (record.sprint ? (context.sprints[record.sprint] ?? record.sprint) : null),
	},
	{
		key: "complexity",
		label: "Points",
		kinds: ["card"],
		numeric: true,
		value: (record) => record.complexity ?? null,
		cell: (record) =>
			record.complexity != null && (
				<span className={record.complexity > SPLIT_ABOVE ? "split" : undefined}>{record.complexity}</span>
			),
	},
	{
		key: "timebox",
		label: "Timebox",
		kinds: ["card"],
		numeric: true,
		value: (record) => record.timebox_mins ?? null,
		cell: (record) => record.timebox_mins != null && `${record.timebox_mins}m`,
	},
	{
		key: "blocked",
		label: "Blocked",
		kinds: ["card"],
		wide: true,
		value: (record) => record.blocked ?? null,
		cell: (record) => record.blocked && <span className="cell-blocked">{record.blocked}</span>,
	},
	{
		key: "dependent_on",
		label: "Waits on",
		kinds: ["card"],
		value: (record) => (record.dependent_on ?? []).join(", ") || null,
	},
	{ key: "session", label: "Claimed by", value: (record) => record.session ?? null },
	{
		key: "due",
		label: "Due",
		kinds: ["card"],
		value: (record) => record.due ?? null,
		cell: (record) => {
			const due = dueState(record);
			return due && <span className={`due-${due.tone}`}>{shortDate(record.due)}</span>;
		},
	},
	{ key: "prs", label: "PRs", kinds: ["card"], wide: true, value: (record) => record.prs ?? null },
	{
		key: "cost",
		label: "Cost",
		kinds: ["card"],
		numeric: true,
		value: (record) => record.cost_usd ?? null,
		cell: (record) => record.cost_usd != null && `$${record.cost_usd.toFixed(2)}`,
	},
	{
		key: "tokens",
		label: "Tokens",
		kinds: ["card"],
		numeric: true,
		value: (record) => record.tokens_k ?? null,
		cell: (record) => record.tokens_k != null && `${record.tokens_k}k`,
	},
	{ key: "comments", label: "Threads", numeric: true, value: (record) => record.comments || null },
	{
		key: "rework",
		label: "Back from",
		kinds: ["card"],
		numeric: true,
		value: (record) => reworkOf(record) || null,
		cell: (record) =>
			bounces(record)
				.map(([gate, count]) => `${gate} ${count}`)
				.join(", "),
	},
	...MODEL_STAGES.map(
		(stage): Column => ({
			key: `model:${stage}`,
			label: `${stage} model`,
			kinds: ["card"],
			value: (record) => record.models?.[stage] ?? null,
		}),
	),
	{
		key: "days",
		label: "Days in column",
		numeric: true,
		value: (record) => record.days_in_column ?? null,
	},
	{ key: "created", label: "Created", value: (record) => record.created, cell: (record) => <Stamp stamp={record.created} /> },
	{
		key: "moved",
		label: "Last moved",
		value: (record) => lastMoved(record),
		cell: (record) => <Stamp stamp={lastMoved(record)} />,
	},
];

function dateColumn(column: string): Column {
	return {
		key: `date:${column}`,
		label: column,
		value: (record) => record.dates?.[column] ?? null,
		cell: (record) => <Stamp stamp={record.dates?.[column]} />,
	};
}

export function tableColumns(kind: Kind, records: Card[]) {
	const dated = new Set(records.flatMap((record) => Object.keys(record.dates ?? {})));
	const ordered = boardColumns(kind).filter((column) => dated.has(column));
	const extra = [...dated].filter((column) => !ordered.includes(column)).sort();
	return [
		...COLUMNS.filter((column) => !column.kinds || column.kinds.includes(kind)),
		...[...ordered, ...extra].map(dateColumn),
	];
}

export function contextOf(kind: Kind, lists: Lists): Context {
	return {
		epics: Object.fromEntries(lists.epics.map((epic) => [epic.id, epic.name])),
		epicProjects: Object.fromEntries(lists.epics.map((epic) => [epic.id, epic.project])),
		sprints: Object.fromEntries(lists.sprints.map((sprint) => [sprint.id, sprint.name])),
		projects: Object.fromEntries(lists.projects.map((project) => [project.id, project.name])),
		columns: boardColumns(kind),
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

export function sortTable(records: Card[], columns: Column[], context: Context, sort: TableSort) {
	const column = sort && columns.find((candidate) => candidate.key === sort.key);
	if (!sort || !column) return records;
	const keyed = records.map((record) => ({ record, value: column.value(record, context) }));
	keyed.sort((a, b) => {
		if (a.value == null || a.value === "") return b.value == null || b.value === "" ? 0 : 1;
		if (b.value == null || b.value === "") return -1;
		const order = compare(a.value, b.value);
		return sort.descending ? -order : order;
	});
	return keyed.map(({ record }) => record);
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
	records,
	columns,
	context,
	sort,
	onSort,
	pending,
	focusedId,
	selected,
	onOpen,
}: {
	kind: Kind;
	records: Card[];
	columns: Column[];
	context: Context;
	sort: TableSort;
	onSort: (key: string) => void;
	pending: Set<string>;
	focusedId: string | null;
	selected: Set<string>;
	onOpen: (id: string, toggle: boolean) => void;
}) {
	return (
		<div className="table-wrap">
			<table className="records">
				<thead>
					<tr>
						{columns.map((column) => (
							<Header key={column.key} column={column} sort={sort} onSort={onSort} />
						))}
					</tr>
				</thead>
				<tbody>
					{records.map((record) => (
						<tr
							key={record.id}
							className={
								[
									pending.has(record.id) && "pending",
									focusedId === record.id && "focused",
									selected.has(record.id) && "selected",
								]
									.filter(Boolean)
									.join(" ") || undefined
							}
							onClick={(event) => {
								if ((event.target as HTMLElement).closest("button")) return;
								onOpen(record.id, event.shiftKey || event.metaKey || event.ctrlKey);
							}}
						>
							<th scope="row">
								<button
									type="button"
									className="ident"
									data-card={record.id}
									aria-pressed={selected.has(record.id) || undefined}
									onClick={(event) => onOpen(record.id, event.shiftKey || event.metaKey || event.ctrlKey)}
								>
									{record.id}
								</button>
							</th>
							<td className="cell-name" title={record.name}>
								{record.icon && <span className="record-icon">{record.icon}</span>}
								{record.name}
							</td>
							{columns.slice(2).map((column) => {
								const shown = column.cell ? column.cell(record, context) : column.value(record, context);
								const text = column.value(record, context);
								return (
									<td
										key={column.key}
										className={[column.numeric && "numeric", column.wide && "wide"].filter(Boolean).join(" ") || undefined}
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
			{records.length === 0 && <p className="table-empty">No {kind} matches the view and the filters.</p>}
		</div>
	);
}
