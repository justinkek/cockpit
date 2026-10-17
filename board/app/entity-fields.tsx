"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, useTransition } from "react";
import { editCard } from "@/app/tracked";
import { EmojiPicker } from "@/app/emoji-picker";
import { Choice, Fallback, type Handlers, type Lists, TextField } from "@/app/fields";
import { type Card, DOMAINS, FIBONACCI, PROJECT_STATUSES, entityKindOf, pageOf } from "@/lib/shared";

type Edit = Handlers["onEdit"];

function IconField({ entity, onEdit }: { entity: Card; onEdit: Edit }) {
	return (
		<>
			<dt>Icon</dt>
			<dd>
				<Fallback id={entity.id} op="set" field="icon">
					<EmojiPicker value={entity.icon ?? ""} onPick={(icon) => onEdit("icon", icon, { icon: icon || null })} />
				</Fallback>
			</dd>
		</>
	);
}

function NumberField({
	entity,
	field,
	label,
	placeholder,
	min = 0,
	step,
	onEdit,
}: {
	entity: Card;
	field: "priority" | "dev_days" | "speed";
	label: string;
	placeholder: string;
	min?: number;
	step?: string;
	onEdit: Edit;
}) {
	const value = entity[field];
	return (
		<>
			<dt>{label}</dt>
			<dd>
				<Fallback id={entity.id} op="set" field={field}>
					<TextField
						type="number"
						label={label}
						placeholder={placeholder}
						min={min}
						step={step}
						value={value == null ? "" : String(value)}
						onCommit={(next) => onEdit(field, next, { [field]: next === "" ? null : Number(next) })}
					/>
				</Fallback>
			</dd>
		</>
	);
}

function ProjectFields({ entity, onEdit }: { entity: Card; onEdit: Edit }) {
	const id = entity.id;
	return (
		<>
			<dt>Status</dt>
			<dd>
				<Fallback id={id} op="set" field="status">
					<select
						name="value"
						aria-label="Status"
						value={entity.status ?? ""}
						onChange={(event) => onEdit("status", event.target.value, { status: event.target.value })}
					>
						{!PROJECT_STATUSES.some((status) => status === entity.status) && (
							<option disabled value={entity.status ?? ""}>
								{entity.status || "No status"}
							</option>
						)}
						{PROJECT_STATUSES.map((status) => (
							<option key={status}>{status}</option>
						))}
					</select>
				</Fallback>
			</dd>
			<IconField entity={entity} onEdit={onEdit} />
			<dt>Key</dt>
			<dd className="stack">
				<Fallback id={id} op="set" field="key">
					<TextField
						label="Key"
						placeholder="2 to 4 letters - changing it renumbers the project's tickets"
						value={entity.key ?? ""}
						onCommit={(key) => onEdit("key", key.toUpperCase(), { key: key.toUpperCase() || null })}
					/>
				</Fallback>
			</dd>
			<NumberField
				entity={entity}
				field="priority"
				label="Priority"
				placeholder="No priority - 1 comes first"
				onEdit={onEdit}
			/>
			<dt>Repo</dt>
			<dd className="stack">
				<Fallback id={id} op="set" field="repo">
					<TextField
						type="url"
						label="Repo"
						placeholder="No repository - a URL"
						value={entity.repo ?? ""}
						onCommit={(repo) => onEdit("repo", repo, { repo: repo || null })}
					/>
				</Fallback>
				{entity.repo && (
					<a href={entity.repo} target="_blank" rel="noreferrer" className="pr-link">
						{entity.repo.replace(/^https?:\/\/(www\.)?/, "")}
					</a>
				)}
			</dd>
		</>
	);
}

function LongField({
	entity,
	field,
	label,
	placeholder,
	onEdit,
}: {
	entity: Card;
	field: "why" | "description";
	label: string;
	placeholder: string;
	onEdit: Edit;
}) {
	const value = entity[field] ?? "";
	const [draft, setDraft] = useState(value);
	const cancelled = useRef(false);
	useEffect(() => setDraft(value), [value]);
	return (
		<>
			<dt>{label}</dt>
			<dd>
				<Fallback id={entity.id} op="set" field={field}>
					<textarea
						name="value"
						className="long-field"
						aria-label={label}
						placeholder={placeholder}
						rows={3}
						value={draft}
						onChange={(event) => setDraft(event.target.value)}
						onKeyDown={(event) => {
							if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
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
							const next = draft.trim();
							if (next !== value) onEdit(field, next, { [field]: next || null });
						}}
					/>
				</Fallback>
			</dd>
		</>
	);
}

function ReferenceFields({ entity, lists, onEdit }: { entity: Card; lists: Lists; onEdit: Edit }) {
	const id = entity.id;
	return (
		<>
			<dt>Points</dt>
			<dd>
				<Fallback id={id} op="set" field="points">
					<select
						name="value"
						aria-label="Points"
						value={entity.points ?? ""}
						onChange={(event) => {
							const value = event.target.value;
							onEdit("points", value, { points: value === "" ? null : Number(value) });
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
			<dt>Domain</dt>
			<dd>
				<Fallback id={id} op="set" field="domain">
					<select
						name="value"
						aria-label="Domain"
						value={entity.domain ?? ""}
						onChange={(event) => onEdit("domain", event.target.value, { domain: event.target.value || null })}
					>
						<option value="">No domain</option>
						{DOMAINS.map((domain) => (
							<option key={domain}>{domain}</option>
						))}
					</select>
				</Fallback>
			</dd>
			<dt>Stack</dt>
			<dd>
				<Fallback id={id} op="set" field="stack">
					<TextField
						label="Stack"
						placeholder="No stack - React Native, Shell…"
						value={entity.stack ?? ""}
						onCommit={(stack) => onEdit("stack", stack, { stack: stack || null })}
					/>
				</Fallback>
			</dd>
			<dt>Taken from</dt>
			<dd className="with-link">
				<Fallback id={id} op="set" field="card">
					<Choice
						label="Taken from"
						none="No ticket"
						value={entity.card}
						options={lists.cards.map((card) => ({ id: card.id, name: `${card.id} · ${card.name}` }))}
						onChange={(card) => onEdit("card", card, { card: card || null })}
					/>
				</Fallback>
				{entity.card && (
					<Link href={pageOf(entity.card)} className="quiet-link" aria-label="Open the ticket">
						↗
					</Link>
				)}
			</dd>
			<IconField entity={entity} onEdit={onEdit} />
			<LongField entity={entity} field="why" label="Why" placeholder="Why it is sized as it is" onEdit={onEdit} />
			<LongField
				entity={entity}
				field="description"
				label="Description"
				placeholder="What a change of this size looks like"
				onEdit={onEdit}
			/>
		</>
	);
}

function DateField({ entity, field, onEdit }: { entity: Card; field: "start" | "end" | "date"; onEdit: Edit }) {
	const label = field === "start" ? "Start" : field === "end" ? "End" : "Date";
	return (
		<Fallback id={entity.id} op="set" field={field}>
			<TextField
				type="date"
				label={label}
				required={field === "date"}
				value={entity[field] ?? ""}
				onCommit={(date) => onEdit(field, date, { [field]: date || null })}
			/>
		</Fallback>
	);
}

function SprintFields({ entity, onEdit }: { entity: Card; onEdit: Edit }) {
	return (
		<>
			<dt>Start</dt>
			<dd>
				<DateField entity={entity} field="start" onEdit={onEdit} />
			</dd>
			<dt>End</dt>
			<dd>
				<DateField entity={entity} field="end" onEdit={onEdit} />
			</dd>
			<NumberField
				entity={entity}
				field="dev_days"
				label="Dev days"
				placeholder="Working days in it"
				step="any"
				onEdit={onEdit}
			/>
			<NumberField entity={entity} field="speed" label="Speed" placeholder="Points a day" step="any" onEdit={onEdit} />
			<IconField entity={entity} onEdit={onEdit} />
		</>
	);
}

export function SprintDates({ sprint }: { sprint: Card }) {
	const router = useRouter();
	const [entity, setEntity] = useState(sprint);
	const [error, setError] = useState("");
	const [saving, startTransition] = useTransition();
	useEffect(() => setEntity(sprint), [sprint]);
	const onEdit: Edit = (field, value, change) => {
		const before = entity;
		setEntity((current) => ({ ...current, ...change }));
		setError("");
		startTransition(async () => {
			const result = await editCard(entity.id, field, value);
			if (result.error) {
				setEntity(before);
				setError(result.error);
				if (result.archived) router.refresh();
				return;
			}
			router.refresh();
		});
	};
	return (
		<div className="sprint-dates" aria-label={`Dates of ${entity.name}`}>
			<label>
				<span>Start</span>
				<DateField entity={entity} field="start" onEdit={onEdit} />
			</label>
			<label>
				<span>End</span>
				<DateField entity={entity} field="end" onEdit={onEdit} />
			</label>
			<Link href={pageOf(entity.id)} className="quiet-link">
				Dev days and speed
			</Link>
			{saving && <span className="saving">Saving…</span>}
			{error && (
				<p className="notice error" role="alert">
					{error}
				</p>
			)}
		</div>
	);
}

export function EntityFields({ entity, lists, onEdit }: { entity: Card; lists: Lists; onEdit: Edit }) {
	const kind = entityKindOf(entity.id);
	return (
		<dl className="props">
			{kind === "project" && <ProjectFields entity={entity} onEdit={onEdit} />}
			{kind === "sprint" && <SprintFields entity={entity} onEdit={onEdit} />}
			{kind === "reference" && <ReferenceFields entity={entity} lists={lists} onEdit={onEdit} />}
			{kind === "milestone" && (
				<>
					<dt>Date</dt>
					<dd className="with-link">
						<DateField entity={entity} field="date" onEdit={onEdit} />
						<Link href="/plan" className="quiet-link" aria-label="Open the plan">
							↗
						</Link>
					</dd>
					<IconField entity={entity} onEdit={onEdit} />
				</>
			)}
		</dl>
	);
}
