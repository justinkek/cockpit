"use client";

import { Fallback, type Handlers, type Lists, TextField } from "@/app/fields";
import { type Card, PROJECT_STATUSES, recordKindOf } from "@/lib/shared";

type Edit = Handlers["onEdit"];

function IconField({ record, onEdit }: { record: Card; onEdit: Edit }) {
	return (
		<>
			<dt>Icon</dt>
			<dd>
				<Fallback id={record.id} op="set" field="icon">
					<TextField
						label="Icon"
						placeholder="No icon - one emoji"
						value={record.icon ?? ""}
						onCommit={(icon) => onEdit("icon", icon, { icon: icon || null })}
					/>
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

export function RecordFields({ record, onEdit }: { record: Card; lists: Lists; onEdit: Edit }) {
	const kind = recordKindOf(record.id);
	return (
		<dl className="props">
			{kind === "project" && <ProjectFields record={record} onEdit={onEdit} />}
		</dl>
	);
}
