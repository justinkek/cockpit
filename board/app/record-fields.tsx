"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, useTransition } from "react";
import { editCard } from "@/app/actions";
import { EmojiPicker } from "@/app/emoji-picker";
import { Choice, Fallback, type Handlers, type Lists, TextField } from "@/app/fields";
import { type Card, DOMAINS, FIBONACCI, PROJECT_STATUSES, recordKindOf } from "@/lib/shared";

type Edit = Handlers["onEdit"];

function IconField({ record, onEdit }: { record: Card; onEdit: Edit }) {
	return (
		<>
			<dt>Icon</dt>
			<dd>
				<Fallback id={record.id} op="set" field="icon">
					<EmojiPicker value={record.icon ?? ""} onPick={(icon) => onEdit("icon", icon, { icon: icon || null })} />
				</Fallback>
			</dd>
		</>
	);
}

function NumberField({
	record,
	field,
	label,
	placeholder,
	min = 0,
	step,
	onEdit,
}: {
	record: Card;
	field: "priority" | "dev_days" | "speed";
	label: string;
	placeholder: string;
	min?: number;
	step?: string;
	onEdit: Edit;
}) {
	const value = record[field];
	return (
		<>
			<dt>{label}</dt>
			<dd>
				<Fallback id={record.id} op="set" field={field}>
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

function ProjectFields({ record, onEdit }: { record: Card; onEdit: Edit }) {
	const id = record.id;
	return (
		<>
			<dt>Status</dt>
			<dd>
				<Fallback id={id} op="set" field="status">
					<select
						name="value"
						aria-label="Status"
						value={record.status ?? ""}
						onChange={(event) => onEdit("status", event.target.value, { status: event.target.value })}
					>
						{!PROJECT_STATUSES.some((status) => status === record.status) && (
							<option disabled value={record.status ?? ""}>
								{record.status || "No status"}
							</option>
						)}
						{PROJECT_STATUSES.map((status) => (
							<option key={status}>{status}</option>
						))}
					</select>
				</Fallback>
			</dd>
			<IconField record={record} onEdit={onEdit} />
			<NumberField record={record} field="priority" label="Priority" placeholder="No priority - 1 comes first" onEdit={onEdit} />
			<dt>Repo</dt>
			<dd className="stack">
				<Fallback id={id} op="set" field="repo">
					<TextField
						type="url"
						label="Repo"
						placeholder="No repository - a URL"
						value={record.repo ?? ""}
						onCommit={(repo) => onEdit("repo", repo, { repo: repo || null })}
					/>
				</Fallback>
				{record.repo && (
					<a href={record.repo} target="_blank" rel="noreferrer" className="pr-link">
						{record.repo.replace(/^https?:\/\/(www\.)?/, "")}
					</a>
				)}
			</dd>
		</>
	);
}

function LongField({
	record,
	field,
	label,
	placeholder,
	onEdit,
}: {
	record: Card;
	field: "why" | "description";
	label: string;
	placeholder: string;
	onEdit: Edit;
}) {
	const value = record[field] ?? "";
	const [draft, setDraft] = useState(value);
	const cancelled = useRef(false);
	useEffect(() => setDraft(value), [value]);
	return (
		<>
			<dt>{label}</dt>
			<dd>
				<Fallback id={record.id} op="set" field={field}>
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

function ReferenceFields({ record, lists, onEdit }: { record: Card; lists: Lists; onEdit: Edit }) {
	const id = record.id;
	return (
		<>
			<dt>Points</dt>
			<dd>
				<Fallback id={id} op="set" field="points">
					<select
						name="value"
						aria-label="Points"
						value={record.points ?? ""}
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
						value={record.domain ?? ""}
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
						value={record.stack ?? ""}
						onCommit={(stack) => onEdit("stack", stack, { stack: stack || null })}
					/>
				</Fallback>
			</dd>
			<dt>Taken from</dt>
			<dd className="with-link">
				<Fallback id={id} op="set" field="card">
					<Choice
						label="Taken from"
						none="No card"
						value={record.card}
						options={lists.cards.map((card) => ({ id: card.id, name: `${card.id} · ${card.name}` }))}
						onChange={(card) => onEdit("card", card, { card: card || null })}
					/>
				</Fallback>
				{record.card && (
					<Link href={`/card/${record.card}`} className="quiet-link" aria-label="Open the card">
						↗
					</Link>
				)}
			</dd>
			<IconField record={record} onEdit={onEdit} />
			<LongField record={record} field="why" label="Why" placeholder="Why it is sized as it is" onEdit={onEdit} />
			<LongField
				record={record}
				field="description"
				label="Description"
				placeholder="What a change of this size looks like"
				onEdit={onEdit}
			/>
		</>
	);
}

function DateField({ record, field, onEdit }: { record: Card; field: "start" | "end"; onEdit: Edit }) {
	const label = field === "start" ? "Start" : "End";
	return (
		<Fallback id={record.id} op="set" field={field}>
			<TextField
				type="date"
				label={label}
				value={record[field] ?? ""}
				onCommit={(date) => onEdit(field, date, { [field]: date || null })}
			/>
		</Fallback>
	);
}

function SprintFields({ record, onEdit }: { record: Card; onEdit: Edit }) {
	return (
		<>
			<dt>Start</dt>
			<dd>
				<DateField record={record} field="start" onEdit={onEdit} />
			</dd>
			<dt>End</dt>
			<dd>
				<DateField record={record} field="end" onEdit={onEdit} />
			</dd>
			<NumberField record={record} field="dev_days" label="Dev days" placeholder="Working days in it" step="any" onEdit={onEdit} />
			<NumberField record={record} field="speed" label="Speed" placeholder="Points a day" step="any" onEdit={onEdit} />
			<IconField record={record} onEdit={onEdit} />
		</>
	);
}

export function SprintDates({ sprint }: { sprint: Card }) {
	const router = useRouter();
	const [record, setRecord] = useState(sprint);
	const [error, setError] = useState("");
	const [saving, startTransition] = useTransition();
	useEffect(() => setRecord(sprint), [sprint]);
	const onEdit: Edit = (field, value, change) => {
		const before = record;
		setRecord((current) => ({ ...current, ...change }));
		setError("");
		startTransition(async () => {
			const result = await editCard(record.id, field, value);
			if (result.error) {
				setRecord(before);
				setError(result.error);
				return;
			}
			router.refresh();
		});
	};
	return (
		<div className="sprint-dates" aria-label={`Dates of ${record.name}`}>
			<label>
				<span>Start</span>
				<DateField record={record} field="start" onEdit={onEdit} />
			</label>
			<label>
				<span>End</span>
				<DateField record={record} field="end" onEdit={onEdit} />
			</label>
			<Link href={`/card/${record.id}`} className="quiet-link">
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

export function RecordFields({ record, lists, onEdit }: { record: Card; lists: Lists; onEdit: Edit }) {
	const kind = recordKindOf(record.id);
	return (
		<dl className="props">
			{kind === "project" && <ProjectFields record={record} onEdit={onEdit} />}
			{kind === "sprint" && <SprintFields record={record} onEdit={onEdit} />}
			{kind === "reference" && <ReferenceFields record={record} lists={lists} onEdit={onEdit} />}
		</dl>
	);
}
