"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { Fragment, useEffect, useId, useRef, useState, useTransition } from "react";
import { dropCard, editCard, linkCards } from "@/app/actions";
import { Content } from "@/app/content";
import { boardColumns, type Card, FIBONACCI, kindOf, type Named, type Sprint, TYPES } from "@/lib/shared";

type Result = { record?: Card; error?: string };
type Picked = Named & { status: string };

function TextField({
	value,
	onCommit,
	label,
	placeholder,
	type = "text",
	className,
	required,
}: {
	value: string;
	onCommit: (value: string) => void;
	label: string;
	placeholder?: string;
	type?: "text" | "date" | "number";
	className?: string;
	required?: boolean;
}) {
	const [draft, setDraft] = useState(value);
	const cancelled = useRef(false);
	useEffect(() => setDraft(value), [value]);
	return (
		<input
			type={type}
			className={className}
			aria-label={label}
			placeholder={placeholder}
			value={draft}
			min={type === "number" ? 1 : undefined}
			onChange={(event) => setDraft(event.target.value)}
			onKeyDown={(event) => {
				if (event.key === "Enter") event.currentTarget.blur();
				if (event.key === "Escape") {
					cancelled.current = true;
					event.currentTarget.blur();
				}
			}}
			onBlur={() => {
				const next = draft.trim();
				if (cancelled.current || (required && next === "")) {
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
	onUnlink,
}: {
	ids: string[];
	names: Record<string, string>;
	onUnlink: (id: string) => void;
}) {
	if (ids.length === 0) return <p className="empty">None</p>;
	return (
		<ul>
			{ids.map((id) => (
				<li key={id}>
					<Link href={`/card/${id}`} className="chip">
						{id}
					</Link>
					<span className="linked-name">{names[id] ?? ""}</span>
					<button type="button" className="quiet" aria-label={`Unlink ${id}`} onClick={() => onUnlink(id)}>
						Unlink
					</button>
				</li>
			))}
		</ul>
	);
}

export function Ticket({
	initial,
	cards,
	epics,
	sprints,
	projects,
}: {
	initial: Card;
	cards: Picked[];
	epics: Named[];
	sprints: Sprint[];
	projects: Named[];
}) {
	const router = useRouter();
	const [record, setRecord] = useState(initial);
	const [error, setError] = useState("");
	const [saving, startTransition] = useTransition();

	useEffect(() => setRecord(initial), [initial]);

	const kind = kindOf(record.id);
	const columns = kind ? boardColumns(kind) : [];
	const names = Object.fromEntries(cards.map((card) => [card.id, card.name]));
	const children = record.dependent_on ?? [];
	const parents = record.dependency_for ?? [];
	const linkable = cards.filter((card) => card.id !== record.id);
	const dates = Object.entries(record.dates ?? {}).sort(([, a], [, b]) => a.localeCompare(b));

	function save(change: Partial<Card>, request: () => Promise<Result>) {
		const before = record;
		setRecord((current) => ({ ...current, ...change }));
		setError("");
		startTransition(async () => {
			const result = await request();
			if (result.error) {
				setRecord(before);
				setError(result.error);
				return;
			}
			if (!result.record) return;
			setRecord(result.record);
			if (result.record.id !== before.id) router.replace(`/card/${result.record.id}`);
		});
	}

	function edit(field: string, value: string, change: Partial<Card>) {
		save(change, () => editCard(record.id, field, value));
	}

	function relink(parent: string, child: string, linked: boolean) {
		save({}, () => linkCards(record.id, parent, child, linked));
	}

	const sprintOptions = sprints.map((sprint) => ({
		id: sprint.id,
		name: sprint.start ? `${sprint.name} (${sprint.start} to ${sprint.end ?? "?"})` : sprint.name,
	}));

	return (
		<article className="stub">
			<TextField
				className="title-input"
				label="Name"
				value={record.name}
				required
				onCommit={(name) => edit("name", name, { name })}
			/>
			<p className="meta">
				<span>{record.id}</span>
				{record.type && <span>{record.type}</span>}
				<span>{record.status}</span>
				{saving && <span className="saving">Saving…</span>}
			</p>
			{error && (
				<p className="notice error" role="alert">
					<span>{error}</span>
					<button type="button" className="quiet" onClick={() => setError("")}>
						Dismiss
					</button>
				</p>
			)}

			<dl className="props">
				<dt>Status</dt>
				<dd>
					{kind ? (
						<select
							aria-label="Status"
							value={record.status}
							onChange={(event) => {
								const status = event.target.value;
								save({ status }, () => dropCard(record.id, status));
							}}
						>
							{!columns.includes(record.status) && <option disabled>{record.status}</option>}
							{columns.map((column) => (
								<option key={column}>{column}</option>
							))}
						</select>
					) : (
						(record.status ?? <span className="empty">None</span>)
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
									edit("type", event.target.value, { type });
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
									edit("complexity", value, { complexity: value === "" ? null : Number(value) });
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
											edit("timebox_mins", value, { timebox_mins: value === "" ? null : Number(value) })
										}
									/>
								</dd>
							</>
						)}
						<dt>Epic</dt>
						<dd>
							<Choice
								label="Epic"
								none="No epic"
								value={record.epic}
								options={epics}
								onChange={(epic) => edit("epic", epic, { epic: epic || null })}
							/>
						</dd>
						<dt>Sprint</dt>
						<dd>
							<Choice
								label="Sprint"
								none="No sprint"
								value={record.sprint}
								options={sprintOptions}
								onChange={(sprint) => edit("sprint", sprint, { sprint: sprint || null })}
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
								options={projects}
								onChange={(project) => edit("project", project, { project: project || null })}
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
								onCommit={(due) => edit("due", due, { due: due || null })}
							/>
						</dd>
						<dt>Blocked</dt>
						<dd>
							<TextField
								label="Blocked"
								placeholder="Not blocked"
								value={record.blocked ?? ""}
								onCommit={(blocked) => edit("blocked", blocked, { blocked: blocked || null })}
							/>
						</dd>
						<dt>PRs</dt>
						<dd>
							<TextField
								label="PRs"
								placeholder="No pull requests"
								value={record.prs ?? ""}
								onCommit={(prs) => edit("prs", prs, { prs: prs || null })}
							/>
						</dd>
					</>
				)}
			</dl>

			{kind === "card" && (
				<section className="links">
					<h2>Dependent on</h2>
					<Linked ids={children} names={names} onUnlink={(child) => relink(record.id, child, false)} />
					<Picker
						label="Add a child"
						cards={linkable.filter((card) => !children.includes(card.id))}
						onPick={(child) => relink(record.id, child, true)}
						onMiss={(text) => setError(`no card called '${text}'`)}
					/>
					<h2>Dependency for</h2>
					<Linked ids={parents} names={names} onUnlink={(parent) => relink(parent, record.id, false)} />
					<Picker
						label="Add a parent"
						cards={linkable.filter((card) => !parents.includes(card.id))}
						onPick={(parent) => relink(parent, record.id, true)}
						onMiss={(text) => setError(`no card called '${text}'`)}
					/>
				</section>
			)}

			<dl className="facts">
				<dt>Claimed by</dt>
				<dd>{record.session ?? <span className="empty">nobody</span>}</dd>
				<dt>Cost</dt>
				<dd>
					{record.cost_usd != null ? `$${record.cost_usd}` : <span className="empty">-</span>}
					{record.tokens_k != null && ` · ${record.tokens_k}k tokens`}
				</dd>
				<dt>Created</dt>
				<dd>{record.created}</dd>
				{dates.map(([column, stamp]) => (
					<Fragment key={column}>
						<dt>Date: {column}</dt>
						<dd>{stamp}</dd>
					</Fragment>
				))}
			</dl>

			<Content id={record.id} body={record.body} onRecord={setRecord} />
		</article>
	);
}
