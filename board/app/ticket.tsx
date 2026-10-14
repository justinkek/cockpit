"use client";

import { useRouter } from "next/navigation";
import { Fragment, useEffect, useState, useTransition } from "react";
import { dropCard, editCard, linkCards, undoChange } from "@/app/actions";
import { Content } from "@/app/content";
import { Fields, type Handlers, Links, type Lists, linkChange, Title } from "@/app/fields";
import { type Undoable, UndoToast, undoable } from "@/app/toast";
import { type Card, fieldName } from "@/lib/shared";

type Result = { record?: Card; error?: string; moved?: string; undo?: string };

export function Ticket({ initial, lists, failure }: { initial: Card; lists: Lists; failure?: string }) {
	const router = useRouter();
	const [record, setRecord] = useState(initial);
	const [error, setError] = useState(failure ?? "");
	const [saving, startTransition] = useTransition();
	const [toast, setToast] = useState<Undoable | null>(null);
	const [undoing, setUndoing] = useState(false);

	useEffect(() => setRecord(initial), [initial]);

	useEffect(() => {
		const url = new URL(window.location.href);
		if (!url.searchParams.has("error")) return;
		url.searchParams.delete("error");
		router.replace(`${url.pathname}${url.search}`, { scroll: false });
	}, [router, failure]);

	useEffect(() => {
		if (failure) setError(failure);
	}, [failure]);

	const dates = Object.entries(record.dates ?? {}).sort(([, a], [, b]) => a.localeCompare(b));

	function save(change: Partial<Card>, request: () => Promise<Result>, label: string) {
		const before = record;
		setRecord((current) => ({ ...current, ...change }));
		setError("");
		startTransition(async () => {
			const result = await request();
			if (result.error) {
				setRecord(before);
				setError(result.error);
				if (result.moved) router.replace(`/card/${result.moved}?error=${encodeURIComponent(result.error)}`);
				return;
			}
			if (!result.record) return;
			setRecord(result.record);
			setToast(undoable(result.record.id, result.undo, label.replace(before.id, result.record.id)));
			if (result.record.id !== before.id) router.replace(`/card/${result.record.id}`);
		});
	}

	function undo(shown: Undoable) {
		setUndoing(true);
		setError("");
		startTransition(async () => {
			const [change] = shown.changes;
			const result = await undoChange(change.id, change.since);
			setUndoing(false);
			setToast(null);
			if (result.error) {
				setError(`Could not undo: ${result.error}`);
				return;
			}
			if (!result.record) return;
			setRecord(result.record);
			if (result.record.id !== change.id) router.replace(`/card/${result.record.id}`);
			else router.refresh();
		});
	}

	const handlers: Handlers = {
		onMove: (status) => save({ status }, () => dropCard(record.id, status), `Moved ${record.id} to ${status}`),
		onEdit: (field, value, change) =>
			save(change, () => editCard(record.id, field, value), `Changed the ${fieldName(field)} of ${record.id}`),
		onLink: (parent, child, linked) =>
			save(
				linkChange(record, parent, child, linked),
				() => linkCards(record.id, parent, child, linked),
				linked ? `Linked ${parent} to ${child}` : `Unlinked ${parent} from ${child}`,
			),
	};

	return (
		<article className="stub">
			<Title
				id={record.id}
				className="title-input"
				value={record.name}
				onCommit={(name) => handlers.onEdit("name", name, { name })}
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

			<Fields record={record} lists={lists} handlers={handlers} />
			<Links record={record} lists={lists} handlers={handlers} />

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
			<UndoToast toast={toast} busy={undoing} onUndo={undo} onDismiss={() => setToast(null)} />
		</article>
	);
}
