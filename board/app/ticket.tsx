"use client";

import { useRouter } from "next/navigation";
import { Fragment, useEffect, useState, useTransition } from "react";
import { dropCard, editCard, linkCards } from "@/app/actions";
import { Content } from "@/app/content";
import { Fields, type Handlers, Links, type Lists, linkChange, Title } from "@/app/fields";
import type { Card } from "@/lib/shared";

type Result = { record?: Card; error?: string };

export function Ticket({ initial, lists }: { initial: Card; lists: Lists }) {
	const router = useRouter();
	const [record, setRecord] = useState(initial);
	const [error, setError] = useState("");
	const [saving, startTransition] = useTransition();

	useEffect(() => setRecord(initial), [initial]);

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

	const handlers: Handlers = {
		onMove: (status) => save({ status }, () => dropCard(record.id, status)),
		onEdit: (field, value, change) => save(change, () => editCard(record.id, field, value)),
		onLink: (parent, child, linked) =>
			save(linkChange(record, parent, child, linked), () => linkCards(record.id, parent, child, linked)),
		onError: setError,
	};

	return (
		<article className="stub">
			<Title className="title-input" value={record.name} onCommit={(name) => handlers.onEdit("name", name, { name })} />
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
		</article>
	);
}
