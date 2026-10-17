"use client";

import Link from "next/link";
import { type ReactNode, useEffect, useId, useLayoutEffect, useRef, useState, useSyncExternalStore } from "react";
import { submitCard } from "@/app/actions";
import { CardPicker } from "@/app/card-picker";
import { EmojiPicker } from "@/app/emoji-picker";
import { EntityFields } from "@/app/entity-fields";
import { entityOptions, SearchSelect } from "@/app/search-select";
import { CONFIDENCES } from "@/lib/plan";
import {
	boardColumns,
	bounces,
	type Card,
	dueState,
	FIBONACCI,
	kindOf,
	MODEL_STAGES,
	type Named,
	overrunTitle,
	showsOverrun,
	type Sprint,
	TYPES,
} from "@/lib/shared";

export type Picked = Named & { status: string };

export type Lists = {
	cards: Picked[];
	epics: (Named & { project?: string | null; status?: string })[];
	sprints: Sprint[];
	projects: (Named & { status?: string })[];
	aliases?: Record<string, string>;
};

export type Handlers = {
	onMove: (status: string) => void;
	onEdit: (field: string, value: string, change: Partial<Card>) => void;
	onLink: (parent: string, child: string, linked: boolean) => void;
	onOpen?: (id: string) => void;
};

export function linkChange(entity: Card, parent: string, child: string, linked: boolean): Partial<Card> {
	const toggle = (ids: string[] | undefined, id: string) =>
		linked ? [...new Set([...(ids ?? []), id])] : (ids ?? []).filter((other) => other !== id);
	if (parent === entity.id) return { dependent_on: toggle(entity.dependent_on, child) };
	if (child === entity.id) return { dependency_for: toggle(entity.dependency_for, parent) };
	return {};
}

const never = () => () => {};

export function useHydrated() {
	return useSyncExternalStore(
		never,
		() => true,
		() => false,
	);
}

export function Fallback({
	id,
	op,
	field,
	hidden = {},
	label = "Set",
	className = "field-form",
	children,
}: {
	id: string;
	op: "move" | "set" | "link" | "unlink";
	field?: string;
	hidden?: Record<string, string>;
	label?: string;
	className?: string;
	children: ReactNode;
}) {
	const hydrated = useHydrated();
	return (
		<form action={submitCard} className={className}>
			<input type="hidden" name="id" value={id} />
			<input type="hidden" name="op" value={op} />
			{field && <input type="hidden" name="field" value={field} />}
			{Object.entries(hidden).map(([name, value]) => (
				<input key={name} type="hidden" name={name} value={value} />
			))}
			{children}
			{!hydrated && <button type="submit">{label}</button>}
		</form>
	);
}

export function TextField({
	value,
	onCommit,
	label,
	placeholder,
	type = "text",
	required,
	min = 1,
	step,
}: {
	value: string;
	onCommit: (value: string) => void;
	label: string;
	placeholder?: string;
	type?: "text" | "date" | "number" | "url";
	required?: boolean;
	min?: number;
	step?: string;
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
			name="value"
			aria-label={label}
			placeholder={placeholder}
			value={draft}
			min={type === "number" ? min : undefined}
			step={type === "number" ? step : undefined}
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

export function Title({
	id,
	value,
	onCommit,
	className,
}: {
	id: string;
	value: string;
	onCommit: (value: string) => void;
	className: string;
}) {
	const [draft, setDraft] = useState(value);
	const cancelled = useRef(false);
	const box = useRef<HTMLTextAreaElement>(null);
	useEffect(() => setDraft(value), [value]);
	useLayoutEffect(() => {
		const area = box.current;
		if (!area) return;
		const fit = () => {
			area.style.height = "auto";
			area.style.height = `${area.scrollHeight + area.offsetHeight - area.clientHeight}px`;
		};
		fit();
		const watcher = new ResizeObserver(fit);
		watcher.observe(area.parentElement ?? area);
		return () => watcher.disconnect();
	}, [draft]);
	return (
		<Fallback id={id} op="set" field="name" className="title-form">
			<textarea
				ref={box}
				name="value"
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
		</Fallback>
	);
}

export function Choice({
	value,
	options,
	label,
	none,
	required = false,
	onChange,
}: {
	value: string | null | undefined;
	options: { id: string; name: string }[];
	label: string;
	none?: string;
	required?: boolean;
	onChange: (value: string) => void;
}) {
	const known = !value || options.some((option) => option.id === value);
	return (
		<select name="value" aria-label={label} value={value ?? ""} onChange={(event) => onChange(event.target.value)}>
			{!required && <option value="">{none}</option>}
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
	id,
	side,
	label,
	cards,
	onPick,
}: {
	id: string;
	side: "child" | "parent";
	label: string;
	cards: Picked[];
	onPick: (id: string) => void;
}) {
	const [text, setText] = useState("");
	const [missed, setMissed] = useState("");
	const list = useId();
	const hydrated = useHydrated();
	if (hydrated) return <CardPicker label={label} cards={cards} onPick={onPick} />;
	function pick(value: string) {
		const id = idOf(value, cards);
		if (!id) {
			setMissed(`No ticket is called '${value.trim()}'. Type its id or pick one from the list.`);
			return;
		}
		setMissed("");
		onPick(id);
		setText("");
	}
	return (
		<>
			<form
				className="picker"
				action={submitCard}
				onSubmit={(event) => {
					event.preventDefault();
					if (text.trim()) pick(text);
				}}
			>
				<input type="hidden" name="id" value={id} />
				<input type="hidden" name="op" value="link" />
				<input type="hidden" name="side" value={side} />
				<input
					name="value"
					list={list}
					value={text}
					aria-label={label}
					placeholder={`${label}: an id or a name`}
					onChange={(event) => {
						const value = event.target.value;
						const chosen = (event.nativeEvent as InputEvent).inputType === "insertReplacementText";
						setMissed("");
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
				<button type="submit">Link</button>
			</form>
			{missed && (
				<p className="picker-miss" role="alert">
					{missed}
				</p>
			)}
		</>
	);
}

function Linked({
	owner,
	ids,
	pair,
	names,
	onOpen,
	onUnlink,
}: {
	ids: string[];
	owner: string;
	pair: (other: string) => { parent: string; child: string };
	names: Record<string, string>;
	onOpen?: (id: string) => void;
	onUnlink: (id: string) => void;
}) {
	const hydrated = useHydrated();
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
					<Fallback id={owner} op="unlink" hidden={pair(id)} label="Unlink" className="unlink-form">
						{hydrated && (
							<button type="button" className="quiet" aria-label={`Unlink ${id}`} onClick={() => onUnlink(id)}>
								Unlink
							</button>
						)}
					</Fallback>
				</li>
			))}
		</ul>
	);
}

export function labelsOf(text: string) {
	return [...new Set(text.split(",").map((label) => label.trim()).filter(Boolean))];
}

function pullRequests(prs: string) {
	return prs.match(/https?:\/\/[^\s,]+/g) ?? [];
}

export function Fields({ entity, lists, handlers }: { entity: Card; lists: Lists; handlers: Handlers }) {
	const { onMove, onEdit } = handlers;
	const kind = kindOf(entity.id);
	if (!kind) return <EntityFields entity={entity} lists={lists} onEdit={onEdit} />;
	const columns = kind ? boardColumns(kind) : [];
	const sprintOptions = lists.sprints.map((sprint) => ({
		id: sprint.id,
		name: sprint.start ? `${sprint.name} (${sprint.start} to ${sprint.end ?? "?"})` : sprint.name,
	}));
	const urls = pullRequests(entity.prs ?? "");
	const epicProject = entity.epic ? lists.epics.find((epic) => epic.id === entity.epic)?.project : null;
	const inherited = epicProject
		? (lists.projects.find((project) => project.id === epicProject)?.name ?? epicProject)
		: null;
	const back = bounces(entity);
	const days = entity.days_in_column ?? 0;
	const overrunning = showsOverrun(entity);
	const due = dueState(entity);
	const id = entity.id;

	return (
		<dl className="props">
			<dt>Status</dt>
			<dd>
				{kind ? (
					<Fallback id={id} op="move" label="Move">
						<select
							name="value"
							aria-label="Status"
							value={entity.status}
							onChange={(event) => onMove(event.target.value)}
						>
							{!columns.includes(entity.status) && <option disabled>{entity.status}</option>}
							{columns.map((column) => (
								<option key={column}>{column}</option>
							))}
						</select>
					</Fallback>
				) : (
					entity.status
				)}
			</dd>
			{kind && (
				<>
					<dt>Icon</dt>
					<dd>
						<Fallback id={id} op="set" field="icon">
							<EmojiPicker value={entity.icon ?? ""} onPick={(icon) => onEdit("icon", icon, { icon: icon || null })} />
						</Fallback>
					</dd>
				</>
			)}
			{kind === "card" && (
				<>
					<dt>Type</dt>
					<dd>
						<Fallback id={id} op="set" field="type">
							<select
								name="value"
								aria-label="Type"
								value={entity.type}
								onChange={(event) => {
									const type = event.target.value as Card["type"];
									onEdit("type", event.target.value, { type });
								}}
							>
								{TYPES.map((type) => (
									<option key={type}>{type}</option>
								))}
							</select>
						</Fallback>
					</dd>
					<dt>Urgent</dt>
					<dd>
						<Fallback id={id} op="set" field="urgent">
							<label
								className={`urgent-toggle${entity.urgent ? " urgent-pick" : ""}`}
								title="An urgent ticket sits in the Urgent lane at the top of the board and is picked before every other"
							>
								<input
									type="checkbox"
									name="value"
									value="true"
									aria-label="Urgent"
									checked={Boolean(entity.urgent)}
									onChange={(event) => {
										const urgent = event.target.checked;
										onEdit("urgent", urgent ? "true" : "", { urgent });
									}}
								/>
								<input type="hidden" name="value" value="" />
								{entity.urgent ? "Urgent" : "Not urgent"}
							</label>
						</Fallback>
					</dd>
					<dt>Complexity</dt>
					<dd>
						<Fallback id={id} op="set" field="complexity">
							<select
								name="value"
								aria-label="Complexity"
								value={entity.complexity ?? ""}
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
						</Fallback>
					</dd>
					{entity.type !== "Timebox" && (
						<>
							<dt>Estimate</dt>
							<dd>
								<Fallback id={id} op="set" field="estimate">
									<select
										name="value"
										aria-label="Estimate"
										title="The high-level estimate TD gives, which the plan counts until TR sets a complexity"
										value={entity.estimate ?? ""}
										onChange={(event) => {
											const value = event.target.value;
											onEdit("estimate", value, { estimate: value === "" ? null : Number(value) });
										}}
									>
										<option value="">Not set</option>
										{FIBONACCI.filter((points) => points > 0).map((points) => (
											<option key={points} value={points}>
												{points}
											</option>
										))}
									</select>
								</Fallback>
							</dd>
						</>
					)}
					<dt>Timebox (mins)</dt>
					<dd>
						<Fallback id={id} op="set" field="timebox_mins">
							<TextField
								type="number"
								label="Timebox (mins)"
								placeholder={entity.type === "Timebox" ? "No budget" : "No timebox"}
								value={entity.timebox_mins == null ? "" : String(entity.timebox_mins)}
								onCommit={(value) =>
									onEdit("timebox_mins", value, { timebox_mins: value === "" ? null : Number(value) })
								}
							/>
						</Fallback>
					</dd>
					<dt>Epic</dt>
					<dd className="with-link">
						<Fallback id={id} op="set" field="epic">
							<SearchSelect
								label="Epic"
								name="value"
								value={entity.epic ?? ""}
								options={entityOptions(lists.epics, "Epic Done")}
								onChange={(epic) => onEdit("epic", epic, { epic: epic || null })}
							/>
						</Fallback>
						{entity.epic && (
							<Link href={`/epics?open=${entity.epic}`} className="quiet-link" aria-label="Open the epic">
								↗
							</Link>
						)}
					</dd>
					<dt>Sprint</dt>
					<dd>
						<Fallback id={id} op="set" field="sprint">
							<Choice
								label="Sprint"
								none="No sprint"
								value={entity.sprint}
								options={sprintOptions}
								onChange={(sprint) => onEdit("sprint", sprint, { sprint: sprint || null })}
							/>
						</Fallback>
					</dd>
				</>
			)}
			{kind && (
				<>
					<dt>Project</dt>
					<dd>
						{kind === "card" ? (
							<span title="A ticket's project is its epic's">
								{inherited ?? <span className="empty">No project</span>}
							</span>
						) : (
							<Fallback id={id} op="set" field="project">
								<SearchSelect
									label="Project"
									name="value"
									value={entity.project ?? ""}
									options={entityOptions(lists.projects, "Done")}
									onChange={(project) => onEdit("project", project, { project: project || null })}
								/>
							</Fallback>
						)}
					</dd>
				</>
			)}
			{kind && (
				<>
					<dt>Labels</dt>
					<dd>
						<Fallback id={id} op="set" field="labels">
							<TextField
								label="Labels"
								placeholder="No labels, or a list split by commas"
								value={(entity.labels ?? []).join(", ")}
								onCommit={(labels) => onEdit("labels", labels, { labels: labelsOf(labels) })}
							/>
						</Fallback>
					</dd>
				</>
			)}
			{kind === "epic" && (
				<>
					<dt>Start</dt>
					<dd title="Stamped the day it leaves Backlog, and cleared if it moves back">
						{entity.start ?? <span className="empty">When it leaves Backlog</span>}
					</dd>
					<dt>Target</dt>
					<dd className="with-link">
						<Fallback id={id} op="set" field="target">
							<TextField
								type="date"
								label="Target"
								value={entity.target ?? ""}
								onCommit={(target) => onEdit("target", target, { target: target || null })}
							/>
						</Fallback>
						<Link href={`/plan?open=${id}`} className="quiet-link" aria-label="Open it on the plan">
							↗
						</Link>
					</dd>
					<dt>Confidence</dt>
					<dd>
						<Fallback id={id} op="set" field="confidence">
							<select
								name="value"
								aria-label="Confidence"
								value={entity.confidence ?? ""}
								onChange={(event) =>
									onEdit("confidence", event.target.value, { confidence: event.target.value || null })
								}
							>
								<option value="">Not set</option>
								{CONFIDENCES.map((confidence) => (
									<option key={confidence}>{confidence}</option>
								))}
							</select>
						</Fallback>
					</dd>
					<dt>Learning</dt>
					<dd>
						<Fallback id={id} op="set" field="learning">
							<TextField
								label="Learning"
								placeholder="Nothing learnt yet"
								value={entity.learning ?? ""}
								onCommit={(learning) => onEdit("learning", learning, { learning: learning || null })}
							/>
						</Fallback>
					</dd>
				</>
			)}
			{kind === "card" && (
				<>
					<dt>Due</dt>
					<dd className="with-link">
						<Fallback id={id} op="set" field="due">
							<TextField
								type="date"
								label="Due"
								value={entity.due?.slice(0, 10) ?? ""}
								onCommit={(due) => onEdit("due", due, { due: due || null })}
							/>
						</Fallback>
						{due && due.tone !== "later" && (
							<span className={`pill due due-${due.tone}`} title={due.title} suppressHydrationWarning>
								{due.label}
							</span>
						)}
						{due?.held && (
							<Link
								href={`/plan?open=${due.held}`}
								className="pill due held"
								title={`Held to the target of ${due.held} - a new target moves it, and a date set here makes it the ticket's own`}
							>
								{due.held} target
							</Link>
						)}
					</dd>
					<dt>Blocked</dt>
					<dd>
						<Fallback id={id} op="set" field="blocked">
							<TextField
								label="Blocked"
								placeholder="Not blocked"
								value={entity.blocked ?? ""}
								onCommit={(blocked) => onEdit("blocked", blocked, { blocked: blocked || null })}
							/>
						</Fallback>
					</dd>
					<dt>PRs</dt>
					<dd className="stack">
						<Fallback id={id} op="set" field="prs">
							<TextField
								label="PRs"
								placeholder="No pull requests"
								value={entity.prs ?? ""}
								onCommit={(prs) => onEdit("prs", prs, { prs: prs || null })}
							/>
						</Fallback>
						{urls.map((url) => (
							<a key={url} href={url} target="_blank" rel="noreferrer" className="pr-link">
								{url.replace(/^https?:\/\/(www\.)?github\.com\//, "")}
							</a>
						))}
					</dd>
					{(days > 0 || overrunning) && (
						<>
							<dt>In column</dt>
							<dd>
								{days > 0 && (
									<span>
										{days} working {days === 1 ? "day" : "days"}
									</span>
								)}
								{overrunning && (
									<span className="pill overrun" title={overrunTitle(entity)}>
										Overrunning
									</span>
								)}
							</dd>
						</>
					)}
					{back.length > 0 && (
						<>
							<dt>Back from</dt>
							<dd>
								{back.map(([gate, count]) => (
									<span
										key={gate}
										className="pill rework"
										title={`Sent back from ${gate} ${count === 1 ? "once" : `${count} times`}`}
									>
										{gate} ×{count}
									</span>
								))}
							</dd>
						</>
					)}
					<dt>Models</dt>
					<dd className="models">
						{MODEL_STAGES.map((stage) => (
							<span key={stage} className="model">
								<span className="model-stage">{stage}</span>
								<Fallback id={id} op="set" field={`models.${stage}`}>
									<TextField
										label={`${stage} model`}
										placeholder="Not  ENTITYED"
										value={entity.models?.[stage] ?? ""}
										onCommit={(model) => {
											const models = { ...entity.models, [stage]: model };
											if (!model) delete models[stage];
											onEdit(`models.${stage}`, model, { models });
										}}
									/>
								</Fallback>
							</span>
						))}
					</dd>
				</>
			)}
		</dl>
	);
}

export function Links({ entity, lists, handlers }: { entity: Card; lists: Lists; handlers: Handlers }) {
	const kind = kindOf(entity.id);
	if (kind !== "card" && kind !== "epic") return null;
	const { onLink, onOpen } = handlers;
	const pool: Picked[] =
		kind === "epic" ? lists.epics.map(({ id, name, status }) => ({ id, name, status: status ?? "" })) : lists.cards;
	const names = Object.fromEntries(pool.map((card) => [card.id, card.name]));
	const children = entity.dependent_on ?? [];
	const parents = entity.dependency_for ?? [];
	const linkable = pool.filter((card) => card.id !== entity.id);
	const words =
		kind === "epic"
			? {
					children: "Depends on",
					parents: "Needed by",
					child: "Add an epic it depends on",
					parent: "Add an epic that needs it",
				}
			: { children: "Dependent on", parents: "Dependency for", child: "Add a child", parent: "Add a parent" };
	return (
		<section className="links">
			<h3>{words.children}</h3>
			<Linked
				owner={entity.id}
				ids={children}
				pair={(child) => ({ parent: entity.id, child })}
				names={names}
				onOpen={onOpen}
				onUnlink={(child) => onLink(entity.id, child, false)}
			/>
			<Picker
				id={entity.id}
				side="child"
				label={words.child}
				cards={linkable.filter((card) => !children.includes(card.id))}
				onPick={(child) => onLink(entity.id, child, true)}
			/>
			<h3>{words.parents}</h3>
			<Linked
				owner={entity.id}
				ids={parents}
				pair={(parent) => ({ parent, child: entity.id })}
				names={names}
				onOpen={onOpen}
				onUnlink={(parent) => onLink(parent, entity.id, false)}
			/>
			<Picker
				id={entity.id}
				side="parent"
				label={words.parent}
				cards={linkable.filter((card) => !parents.includes(card.id))}
				onPick={(parent) => onLink(parent, entity.id, true)}
			/>
		</section>
	);
}
