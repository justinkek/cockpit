"use client";

import Link from "next/link";
import { useEffect, useId, useLayoutEffect, useRef, useState } from "react";
import { boardColumns, type Card, FIBONACCI, kindOf, type Named, type Sprint, TYPES } from "@/lib/shared";

export type Picked = Named & { status: string };

export type Lists = {
	cards: Picked[];
	epics: Named[];
	sprints: Sprint[];
	projects: Named[];
};

export type Handlers = {
	onMove: (status: string) => void;
	onEdit: (field: string, value: string, change: Partial<Card>) => void;
	onLink: (parent: string, child: string, linked: boolean) => void;
	onError: (message: string) => void;
	onOpen?: (id: string) => void;
};

export function linkChange(record: Card, parent: string, child: string, linked: boolean): Partial<Card> {
	const toggle = (ids: string[] | undefined, id: string) =>
		linked ? [...new Set([...(ids ?? []), id])] : (ids ?? []).filter((other) => other !== id);
	if (parent === record.id) return { dependent_on: toggle(record.dependent_on, child) };
	if (child === record.id) return { dependency_for: toggle(record.dependency_for, parent) };
	return {};
}

function TextField({
	value,
	onCommit,
	label,
	placeholder,
	type = "text",
	required,
}: {
	value: string;
	onCommit: (value: string) => void;
	label: string;
	placeholder?: string;
	type?: "text" | "date" | "number";
	required?: boolean;
}) {
	const [draft, setDraft] = useState(value);
	const cancelled = useRef(false);
	useEffect(() => setDraft(value), [value]);
	function commit(next: string) {
		if (required && next === "") {
			setDraft(value);
			return;
		}
		if (next !== value) onCommit(next);
	}
	return (
		<input
			type={type}
			aria-label={label}
			placeholder={placeholder}
			value={draft}
			min={type === "number" ? 1 : undefined}
			onChange={(event) => setDraft(event.target.value)}
			onKeyDown={(event) => {
				if (event.key === "Enter") {
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
				if (cancelled.current) {
					cancelled.current = false;
					setDraft(value);
					return;
				}
				commit(draft.trim());
			}}
		/>
	);
}

export function Title({ value, onCommit, className }: { value: string; onCommit: (value: string) => void; className: string }) {
	const [draft, setDraft] = useState(value);
	const cancelled = useRef(false);
	const box = useRef<HTMLTextAreaElement>(null);
	useEffect(() => setDraft(value), [value]);
	useLayoutEffect(() => {
		const area = box.current;
		if (!area) return;
		area.style.height = "auto";
		area.style.height = `${area.scrollHeight}px`;
	}, [draft]);
	return (
		<textarea
			ref={box}
			className={className}
			aria-label="Name"
			rows={1}
			value={draft}
			onChange={(event) => setDraft(event.target.value.replace(/\n/g, " "))}
			onKeyDown={(event) => {
				if (event.key === "Enter") {
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
				const next = draft.trim();
				if (cancelled.current || next === "") {
					cancelled.current = false;
					setDraft(value);
					return;
				}
				if (next !== value) onCommit(next);
			}}
		/>
	);
}

function Choice({
	value,
	options,
	label,
	none,
	onChange,
}: {
	value: string | null | undefined;
	options: { id: string; name: string }[];
	label: string;
	none: string;
	onChange: (value: string) => void;
}) {
	const known = !value || options.some((option) => option.id === value);
	return (
		<select aria-label={label} value={value ?? ""} onChange={(event) => onChange(event.target.value)}>
			<option value="">{none}</option>
			{!known && value && (
				<option value={value} disabled>
					{value}
				</option>
			)}
			{options.map((option) => (
				<option key={option.id} value={option.id}>
					{option.name}
				</option>
			))}
		</select>
	);
}

function idOf(text: string, cards: Picked[]) {
	const typed = text
		.trim()
		.match(/^([A-Za-z]+-\d+)\b/)?.[1]
		?.toUpperCase();
	if (typed) return typed;
	const named = cards.find((card) => card.name.toLowerCase() === text.trim().toLowerCase());
	return named?.id ?? null;
}

function Picker({
	label,
	cards,
	onPick,
	onMiss,
}: {
	label: string;
	cards: Picked[];
	onPick: (id: string) => void;
	onMiss: (text: string) => void;
}) {
	const [text, setText] = useState("");
	const list = useId();
	function pick(value: string) {
		const id = idOf(value, cards);
		if (!id) {
			onMiss(value);
			return;
		}
		onPick(id);
		setText("");
	}
	return (
		<form
			className="picker"
			onSubmit={(event) => {
				event.preventDefault();
				if (text.trim()) pick(text);
			}}
		>
			<input
				list={list}
				value={text}
				aria-label={label}
				placeholder={`${label}: an id or a name`}
				onChange={(event) => {
					const value = event.target.value;
					const chosen = (event.nativeEvent as InputEvent).inputType === "insertReplacementText";
					if (chosen && cards.some((card) => card.id === value)) pick(value);
					else setText(value);
				}}
			/>
			<datalist id={list}>
				{cards.map((card) => (
					<option key={card.id} value={card.id}>
						{card.name}
					</option>
				))}
			</datalist>
			<button type="submit" disabled={!text.trim()}>
				Link
			</button>
		</form>
	);
}

function Linked({
	ids,
	names,
	onOpen,
	onUnlink,
}: {
	ids: string[];
	names: Record<string, string>;
	onOpen?: (id: string) => void;
	onUnlink: (id: string) => void;
}) {
	if (ids.length === 0) return <p className="empty">None</p>;
	return (
		<ul>
			{ids.map((id) => (
				<li key={id}>
					{onOpen ? (
						<button type="button" className="ident-link" onClick={() => onOpen(id)}>
							{id}
						</button>
					) : (
						<Link href={`/card/${id}`} className="ident-link">
							{id}
						</Link>
					)}
					<span className="linked-name">{names[id] ?? ""}</span>
					<button type="button" className="quiet" aria-label={`Unlink ${id}`} onClick={() => onUnlink(id)}>
						Unlink
					</button>
				</li>
			))}
		</ul>
	);
}

function pullRequests(prs: string) {
	return prs.match(/https?:\/\/[^\s,]+/g) ?? [];
}

export function Fields({ record, lists, handlers }: { record: Card; lists: Lists; handlers: Handlers }) {
	const { onMove, onEdit } = handlers;
	const kind = kindOf(record.id);
	const columns = kind ? boardColumns(kind) : [];
	const sprintOptions = lists.sprints.map((sprint) => ({
		id: sprint.id,
		name: sprint.start ? `${sprint.name} (${sprint.start} to ${sprint.end ?? "?"})` : sprint.name,
	}));
	const urls = pullRequests(record.prs ?? "");

	return (
		<dl className="props">
			<dt>Status</dt>
			<dd>
				{kind ? (
					<select aria-label="Status" value={record.status} onChange={(event) => onMove(event.target.value)}>
						{!columns.includes(record.status) && <option disabled>{record.status}</option>}
						{columns.map((column) => (
							<option key={column}>{column}</option>
						))}
					</select>
				) : (
					record.status
				)}
			</dd>
			{kind === "card" && (
				<>
					<dt>Type</dt>
					<dd>
						<select
							aria-label="Type"
							value={record.type}
							onChange={(event) => {
								const type = event.target.value as Card["type"];
								onEdit("type", event.target.value, { type });
							}}
						>
							{TYPES.map((type) => (
								<option key={type}>{type}</option>
							))}
						</select>
					</dd>
					<dt>Complexity</dt>
					<dd>
						<select
							aria-label="Complexity"
							value={record.complexity ?? ""}
							onChange={(event) => {
								const value = event.target.value;
								onEdit("complexity", value, { complexity: value === "" ? null : Number(value) });
							}}
						>
							<option value="">Not set</option>
							{FIBONACCI.map((points) => (
								<option key={points} value={points}>
									{points}
								</option>
							))}
						</select>
					</dd>
					{record.type === "Timebox" && (
						<>
							<dt>Timebox (mins)</dt>
							<dd>
								<TextField
									type="number"
									label="Timebox (mins)"
									placeholder="No budget"
									value={record.timebox_mins == null ? "" : String(record.timebox_mins)}
									onCommit={(value) =>
										onEdit("timebox_mins", value, { timebox_mins: value === "" ? null : Number(value) })
									}
								/>
							</dd>
						</>
					)}
					<dt>Epic</dt>
					<dd className="with-link">
						<Choice
							label="Epic"
							none="No epic"
							value={record.epic}
							options={lists.epics}
							onChange={(epic) => onEdit("epic", epic, { epic: epic || null })}
						/>
						{record.epic && (
							<Link href={`/epics?open=${record.epic}`} className="quiet-link" aria-label="Open the epic">
								↗
							</Link>
						)}
					</dd>
					<dt>Sprint</dt>
					<dd>
						<Choice
							label="Sprint"
							none="No sprint"
							value={record.sprint}
							options={sprintOptions}
							onChange={(sprint) => onEdit("sprint", sprint, { sprint: sprint || null })}
						/>
					</dd>
				</>
			)}
			{kind && (
				<>
					<dt>Project</dt>
					<dd>
						<Choice
							label="Project"
							none="No project"
							value={record.project}
							options={lists.projects}
							onChange={(project) => onEdit("project", project, { project: project || null })}
						/>
					</dd>
				</>
			)}
			{kind === "card" && (
				<>
					<dt>Due</dt>
					<dd>
						<TextField
							type="date"
							label="Due"
							value={record.due?.slice(0, 10) ?? ""}
							onCommit={(due) => onEdit("due", due, { due: due || null })}
						/>
					</dd>
					<dt>Blocked</dt>
					<dd>
						<TextField
							label="Blocked"
							placeholder="Not blocked"
							value={record.blocked ?? ""}
							onCommit={(blocked) => onEdit("blocked", blocked, { blocked: blocked || null })}
						/>
					</dd>
					<dt>PRs</dt>
					<dd className="stack">
						<TextField
							label="PRs"
							placeholder="No pull requests"
							value={record.prs ?? ""}
							onCommit={(prs) => onEdit("prs", prs, { prs: prs || null })}
						/>
						{urls.map((url) => (
							<a key={url} href={url} target="_blank" rel="noreferrer" className="pr-link">
								{url.replace(/^https?:\/\/(www\.)?github\.com\//, "")}
							</a>
						))}
					</dd>
				</>
			)}
		</dl>
	);
}

export function Links({ record, lists, handlers }: { record: Card; lists: Lists; handlers: Handlers }) {
	if (kindOf(record.id) !== "card") return null;
	const { onLink, onError, onOpen } = handlers;
	const names = Object.fromEntries(lists.cards.map((card) => [card.id, card.name]));
	const children = record.dependent_on ?? [];
	const parents = record.dependency_for ?? [];
	const linkable = lists.cards.filter((card) => card.id !== record.id);
	const miss = (text: string) => onError(`no card called '${text}'`);
	return (
		<section className="links">
			<h3>Dependent on</h3>
			<Linked ids={children} names={names} onOpen={onOpen} onUnlink={(child) => onLink(record.id, child, false)} />
			<Picker
				label="Add a child"
				cards={linkable.filter((card) => !children.includes(card.id))}
				onPick={(child) => onLink(record.id, child, true)}
				onMiss={miss}
			/>
			<h3>Dependency for</h3>
			<Linked ids={parents} names={names} onOpen={onOpen} onUnlink={(parent) => onLink(parent, record.id, false)} />
			<Picker
				label="Add a parent"
				cards={linkable.filter((card) => !parents.includes(card.id))}
				onPick={(parent) => onLink(parent, record.id, true)}
				onMiss={miss}
			/>
		</section>
	);
}
