"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { Fragment, useEffect, useMemo, useState, useTransition } from "react";
import { dropCard, duplicateCard, editCard, findInContent, linkCards, type Span, undoChange } from "@/app/actions";
import { cardCommands, type Edits, epicPage, movePage, recordCommands, themeCommands } from "@/app/commands";
import { Content } from "@/app/content";
import { Fields, type Handlers, Links, type Lists, linkChange, Title } from "@/app/fields";
import { cardLink, copyText, useKeys } from "@/app/keys";
import { MentionContext, type Mentions, mentionNames } from "@/app/markdown";
import { type Page, Palette } from "@/app/palette";
import { carryTo, takeCarried, toastOf, typingIn, type Undoable, UndoToast, undoable, withNewId } from "@/app/toast";
import { loadView, neighboursIn, type View } from "@/app/view";
import { type Card, contentSearchFailed, fieldName, kindOf } from "@/lib/shared";

type Result = { record?: Card; error?: string; moved?: string; undo?: Span };

export function Ticket({
	initial,
	lists,
	failure,
	column,
}: {
	initial: Card;
	lists: Lists;
	failure?: string;
	column: Card[];
}) {
	const router = useRouter();
	const [record, setRecord] = useState(initial);
	const [error, setError] = useState(failure ?? "");
	const [saving, startTransition] = useTransition();
	const [toast, setToast] = useState<Undoable | null>(null);
	const [undoing, setUndoing] = useState(false);
	const [palette, setPalette] = useState<Page | null>(null);

	const [view, setView] = useState<View | null>(null);

	useEffect(() => setRecord(initial), [initial]);

	useEffect(() => {
		const handed = takeCarried(initial.id);
		if (handed) setToast(handed);
	}, [initial.id]);

	useEffect(() => {
		const kindOfRecord = kindOf(initial.id);
		if (kindOfRecord) setView(loadView(kindOfRecord));
	}, [initial.id]);

	const [found, setFound] = useState<{ query: string; ids: Set<string> } | null>(null);
	const query = view?.query.trim() ?? "";

	useEffect(() => {
		const kindOfRecord = kindOf(initial.id);
		if (query.length < 2 || !kindOfRecord) return;
		let live = true;
		findInContent(kindOfRecord, query).then((result) => {
			if (!live) return;
			if ("ids" in result) setFound({ query, ids: new Set(result.ids) });
			else setError(contentSearchFailed(kindOfRecord, result.error));
		});
		return () => {
			live = false;
		};
	}, [query, initial.id]);

	const epicNames = useMemo(() => Object.fromEntries(lists.epics.map((epic) => [epic.id, epic.name])), [lists.epics]);
	const inContent = found?.query === query ? found.ids : undefined;
	const neighbours = useMemo(
		() => neighboursIn(column, initial.id, view, { names: epicNames, inContent }),
		[column, initial.id, view, epicNames, inContent],
	);

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
		setToast(null);
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
			const shown = undoable(result.record.id, result.undo, withNewId(label, before.id, result.record.id));
			setToast(shown);
			if (result.record.id !== before.id) {
				carryTo(result.record.id, shown);
				router.replace(`/card/${result.record.id}`);
			}
		});
	}

	function undo(shown: Undoable) {
		setUndoing(true);
		setError("");
		startTransition(async () => {
			const [change] = shown.changes;
			const result = await undoChange(change.id, { since: change.since, until: change.until });
			setUndoing(false);
			setToast((current) => (current?.key === shown.key ? null : current));
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

	const mentions = useMemo<Mentions>(
		() => ({
			nameOf: mentionNames([...lists.cards, ...lists.epics]),
			onOpen: (id) => {
				router.push(id.startsWith("EPIC-") ? `/epics?open=${id}` : `/card/${id}`);
				return true;
			},
		}),
		[lists.cards, lists.epics, router],
	);

	const kind = kindOf(record.id);
	const edits: Edits = { label: record.id, move: handlers.onMove, edit: handlers.onEdit, duplicate };

	function duplicate() {
		setError("");
		startTransition(async () => {
			const result = await duplicateCard(record.id);
			if (!result.record) {
				setError(result.error ?? "board-card made nothing");
				return;
			}
			carryTo(result.record.id, toastOf(`Duplicated ${record.id} as ${result.record.id}`));
			router.push(`/card/${result.record.id}`);
		});
	}

	async function copy(asLink: boolean) {
		const copied = await copyText(asLink ? cardLink(record.id) : record.id);
		setToast(
			toastOf(copied ? `Copied ${asLink ? `the link to ${record.id}` : record.id}` : `Could not copy ${record.id}`),
		);
	}

	function rootPage(): Page {
		return {
			title: "Command menu",
			root: true,
			items: [
				...recordCommands(kind, record, lists, edits),
				{ id: "do:copy", group: record.id, label: "Copy id", hint: "Cmd/Ctrl+.", run: () => copy(false) },
				{ id: "do:link", group: record.id, label: "Copy link", run: () => copy(true) },
				{
					id: "go:board",
					group: "Board",
					label: "Show it on the board",
					run: () => router.push(`${kind === "epic" ? "/epics" : "/"}?open=${record.id}`),
				},
				...themeCommands(),
				...cardCommands(
					lists.cards.filter((card) => card.id !== record.id),
					(id) => router.push(`/card/${id}`),
				),
			],
		};
	}

	useKeys((event) => {
		if (palette || event.defaultPrevented) return;
		const command = event.metaKey || event.ctrlKey;
		const typing = typingIn(event.target);
		if (command && !event.shiftKey && event.key.toLowerCase() === "k") {
			event.preventDefault();
			setPalette(rootPage());
		} else if (command && !typing && (event.code === "Period" || event.key === "." || event.key === ">")) {
			event.preventDefault();
			copy(event.shiftKey);
		} else if (!command && !event.altKey && !typing && (event.key === "j" || event.key === "k")) {
			const to = event.key === "j" ? neighbours?.next : neighbours?.previous;
			if (!to) return;
			event.preventDefault();
			router.push(`/card/${to.id}`);
		} else if (!command && !event.altKey && !typing && kind && (event.key === "s" || event.key === "e")) {
			if (event.key === "e" && kind !== "card") return;
			event.preventDefault();
			setPalette(event.key === "s" ? movePage(kind, record.status, edits) : epicPage(lists, record.epic, edits));
		}
	});

	return (
		<article className="stub">
			{neighbours && (
				<nav className="neighbours" aria-label={`Cards in ${record.status}`}>
					{neighbours.previous ? (
						<Link
							href={`/card/${neighbours.previous.id}`}
							title={`Previous: ${neighbours.previous.name} (k)`}
							rel="prev"
						>
							‹ {neighbours.previous.id}
						</Link>
					) : (
						<span className="empty">‹</span>
					)}
					<span className="neighbours-at">
						{neighbours.position} of {neighbours.total} in {record.status}
					</span>
					{neighbours.next ? (
						<Link href={`/card/${neighbours.next.id}`} title={`Next: ${neighbours.next.name} (j)`} rel="next">
							{neighbours.next.id} ›
						</Link>
					) : (
						<span className="empty">›</span>
					)}
				</nav>
			)}
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
				<button
					type="button"
					className="chip-toggle palette-open"
					onClick={() => setPalette(rootPage())}
					title="Command menu (Cmd/Ctrl+K)"
				>
					Commands
				</button>
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

			<MentionContext.Provider value={mentions}>
				<Content id={record.id} body={record.body} onRecord={setRecord} />
			</MentionContext.Provider>
			<UndoToast toast={toast} busy={undoing} onUndo={undo} onDismiss={() => setToast(null)} />
			{palette && <Palette start={palette} onClose={() => setPalette(null)} />}
		</article>
	);
}
