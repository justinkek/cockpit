"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { loadHistory, restoreVersion, type Span } from "@/app/actions";
import { stampText } from "@/app/stages";
import { type Card, fieldName, type HistoryChange, type HistoryComment, type HistoryEntry } from "@/lib/shared";

type Line = { kind: "same" | "added" | "removed"; text: string };

const DIFF_LIMIT = 4_000_000;

export function lineDiff(before: string, after: string): Line[] {
	const from = before === "" ? [] : before.split("\n");
	const to = after === "" ? [] : after.split("\n");
	let start = 0;
	while (start < from.length && start < to.length && from[start] === to[start]) start += 1;
	let end = 0;
	while (
		end < from.length - start &&
		end < to.length - start &&
		from[from.length - 1 - end] === to[to.length - 1 - end]
	)
		end += 1;
	const head = from.slice(0, start).map((text): Line => ({ kind: "same", text }));
	const tail = from.slice(from.length - end).map((text): Line => ({ kind: "same", text }));
	const a = from.slice(start, from.length - end);
	const b = to.slice(start, to.length - end);
	if (a.length * b.length > DIFF_LIMIT) {
		return [
			...head,
			...a.map((text): Line => ({ kind: "removed", text })),
			...b.map((text): Line => ({ kind: "added", text })),
			...tail,
		];
	}
	const lengths = Array.from({ length: a.length + 1 }, () => new Array<number>(b.length + 1).fill(0));
	for (let i = a.length - 1; i >= 0; i -= 1) {
		for (let j = b.length - 1; j >= 0; j -= 1) {
			lengths[i][j] = a[i] === b[j] ? lengths[i + 1][j + 1] + 1 : Math.max(lengths[i + 1][j], lengths[i][j + 1]);
		}
	}
	const middle: Line[] = [];
	let i = 0;
	let j = 0;
	while (i < a.length && j < b.length) {
		if (a[i] === b[j]) {
			middle.push({ kind: "same", text: a[i] });
			i += 1;
			j += 1;
		} else if (lengths[i + 1][j] >= lengths[i][j + 1]) {
			middle.push({ kind: "removed", text: a[i] });
			i += 1;
		} else {
			middle.push({ kind: "added", text: b[j] });
			j += 1;
		}
	}
	for (; i < a.length; i += 1) middle.push({ kind: "removed", text: a[i] });
	for (; j < b.length; j += 1) middle.push({ kind: "added", text: b[j] });
	return [...head, ...middle, ...tail];
}

function valueText(value: unknown): string {
	if (value == null || value === "") return "none";
	if (Array.isArray(value)) return value.length === 0 ? "none" : value.map(valueText).join(", ");
	if (typeof value === "object") return JSON.stringify(value);
	return String(value);
}

function changeText({ field, from, to }: HistoryChange): string {
	if (field === "status") return `Moved from ${valueText(from)} to ${valueText(to)}`;
	if (field === "archived") return to ? "Archived" : "Brought back from the archive";
	if (field === "id") return `Renamed from ${valueText(from)} to ${valueText(to)}`;
	return `${fieldName(field)}: ${valueText(from)} → ${valueText(to)}`;
}

const COMMENT_VERBS: Record<HistoryComment["action"], string> = {
	added: "Commented",
	resolved: "Resolved a thread",
	reopened: "Reopened a thread",
	edited: "Edited a comment",
	deleted: "Deleted a comment",
	removed: "Took a comment away",
};

function whoOf(entry: HistoryEntry): string {
	return entry.by ?? entry.comments[0]?.author ?? entry.author;
}

function BodyDiff({ body }: { body: { from: string; to: string } }) {
	const lines = lineDiff(body.from, body.to);
	const added = lines.filter((line) => line.kind === "added").length;
	const removed = lines.filter((line) => line.kind === "removed").length;
	return (
		<details className="activity-diff">
			<summary>
				Changed the content <span className="diff-added">+{added}</span> <span className="diff-removed">-{removed}</span>
			</summary>
			<pre>
				{lines.map((line, index) => (
					<span key={index} className={`diff-line diff-${line.kind}`}>
						{line.kind === "added" ? "+ " : line.kind === "removed" ? "- " : "  "}
						{line.text}
						{"\n"}
					</span>
				))}
			</pre>
		</details>
	);
}

function Entry({
	entry,
	latest,
	busy,
	onRestore,
}: {
	entry: HistoryEntry;
	latest: boolean;
	busy: boolean;
	onRestore: () => void;
}) {
	const nothing =
		!entry.created &&
		entry.changes.length === 0 &&
		!entry.body &&
		entry.comments.length === 0 &&
		entry.attachments.length === 0;
	return (
		<li className="activity-entry">
			<p className="activity-head">
				<time dateTime={entry.at} title={new Date(entry.at).toLocaleString()} suppressHydrationWarning>
					{stampText(entry.at)}
				</time>
				<span className="activity-who">{whoOf(entry)}</span>
				{entry.session && <span className="activity-session" title="The session the record named">{entry.session}</span>}
				<span className="ident" title={entry.subject}>
					{entry.commit}
				</span>
				{latest ? (
					<span className="activity-current">Current version</span>
				) : (
					<button
						type="button"
						className="quiet"
						disabled={busy}
						onClick={onRestore}
						title="Write the record back as it stood after this change, with an undo"
					>
						Restore to this version
					</button>
				)}
			</p>
			<ul className="activity-changes">
				{entry.created && <li>Created</li>}
				{entry.changes.map((change) => (
					<li key={change.field}>{changeText(change)}</li>
				))}
				{entry.comments.map((comment) => (
					<li key={`${comment.action}-${comment.id}`}>
						{COMMENT_VERBS[comment.action]}
						{comment.text && <q>{comment.text.length > 140 ? `${comment.text.slice(0, 140)}…` : comment.text}</q>}
					</li>
				))}
				{entry.attachments.map((attachment) => (
					<li key={`${attachment.action}-${attachment.name}`}>
						{attachment.action === "added" ? "Attached" : "Removed the attachment"} {attachment.name}
					</li>
				))}
				{entry.body && (
					<li>
						<BodyDiff body={entry.body} />
					</li>
				)}
				{nothing && <li className="empty">{entry.subject}</li>}
			</ul>
		</li>
	);
}

export function Activity({
	id,
	revision,
	onRestored,
}: {
	id: string;
	revision?: string | null;
	onRestored: (record: Card, undo: Span | undefined, label: string) => void;
}) {
	const [entries, setEntries] = useState<HistoryEntry[] | null>(null);
	const [error, setError] = useState("");
	const [busy, startTransition] = useTransition();

	useEffect(() => {
		let live = true;
		loadHistory(id).then((result) => {
			if (!live) return;
			if (result.error) setError(result.error);
			else {
				setError("");
				setEntries(result.entries ?? []);
			}
		});
		return () => {
			live = false;
		};
	}, [id, revision]);

	function restore(entry: HistoryEntry) {
		setError("");
		startTransition(async () => {
			const result = await restoreVersion(id, entry.commit);
			if (result.error || !result.record) {
				setError(`Could not restore ${id}: ${result.error ?? "board-card wrote nothing"}`);
				return;
			}
			onRestored(result.record, result.undo, `Restored ${id} to ${entry.commit}`);
		});
	}

	return (
		<div className="activity">
			{error && (
				<p className="notice error" role="alert">
					<span>{error}</span>
				</p>
			)}
			{entries == null && !error && <p className="empty">Loading the history…</p>}
			{entries && entries.length === 0 && <p className="empty">No history yet</p>}
			{entries && entries.length > 0 && (
				<ol>
					{entries.map((entry, index) => (
						<Entry
							key={entry.commit}
							entry={entry}
							latest={index === 0}
							busy={busy}
							onRestore={() => restore(entry)}
						/>
					))}
				</ol>
			)}
		</div>
	);
}

export function ActivitySection({
	id,
	revision,
	onRestored,
}: {
	id: string;
	revision?: string | null;
	onRestored: (record: Card, undo: Span | undefined, label: string) => void;
}) {
	const [open, setOpen] = useState(false);
	const section = useRef<HTMLDetailsElement>(null);
	useEffect(() => {
		if (section.current?.open) setOpen(true);
	}, []);
	return (
		<details ref={section} className="activity-section" onToggle={(event) => setOpen(event.currentTarget.open)}>
			<summary>
				<h3>Activity</h3>
			</summary>
			{open && <Activity id={id} revision={revision} onRestored={onRestored} />}
		</details>
	);
}
