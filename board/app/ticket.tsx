"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState, useTransition } from "react";
import { ActivitySection } from "@/app/activity";
import {
	archiveOne,
	closeProject,
	dropCard,
	duplicateCard,
	editCard,
	findInContent,
	linkCards,
	type Span,
	undoChange,
} from "@/app/actions";
import {
	cardCommands,
	type Edits,
	epicPage,
	iconCommand,
	movePage,
	recordCommands,
	themeCommands,
} from "@/app/commands";
import { Content, confirmDiscard } from "@/app/content";
import { type Closing, ProjectDoneDialog, projectRefusal } from "@/app/epic-done";
import { EstimateFacts } from "@/app/estimates";
import { Fields, type Handlers, Links, type Lists, linkChange, type Picked, Title } from "@/app/fields";
import { cardLink, copyText, useKeys } from "@/app/keys";
import { attachmentHref, MentionContext, type Mentions, mentionNames } from "@/app/markdown";
import { type Page, Palette } from "@/app/palette";
import { ProgressMeter } from "@/app/progress";
import { Stages, stampText } from "@/app/stages";
import { tableOrder } from "@/app/table";
import {
	carryTo,
	type Change,
	takeCarried,
	toastOf,
	typingIn,
	type Undoable,
	UndoToast,
	undoable,
	withNewId,
} from "@/app/toast";
import { loadView, neighboursIn, type View } from "@/app/view";
import type { Progress } from "@/lib/metrics";
import type { Estimates } from "@/lib/plan";
import {
	type Card,
	contentSearchFailed,
	fieldName,
	homeOf,
	kindOf,
	movedTo,
	phaseOf,
	recordKindOf,
} from "@/lib/shared";

type Result = {
	record?: Card;
	error?: string;
	moved?: string;
	archived?: boolean;
	undo?: Span;
	more?: Change[];
	closed?: Change[];
};

export function Ticket({
	initial,
	lists,
	failure,
	column,
	records,
	attachments = [],
	progresses = {},
	estimates,
	members = [],
}: {
	initial: Card;
	lists: Lists;
	failure?: string;
	column: Card[];
	records: Card[];
	attachments?: string[];
	progresses?: Record<string, Progress>;
	estimates?: Estimates;
	members?: Picked[];
}) {
	const router = useRouter();
	const [record, setRecord] = useState(initial);
	const [error, setError] = useState(failure ?? "");
	const [saving, startTransition] = useTransition();
	const [toast, setToast] = useState<Undoable | null>(null);
	const [undoing, setUndoing] = useState(false);
	const [palette, setPalette] = useState<Page | null>(null);
	const [closing, setClosing] = useState<Closing | null>(null);

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
	const neighbours = useMemo(() => {
		const kindOfRecord = kindOf(initial.id);
		const found = { names: epicNames, inContent };
		if (view?.layout !== "table" || !kindOfRecord) return neighboursIn(column, initial.id, view, found);
		const tableSort = view.tableSort;
		return neighboursIn(records, initial.id, view, found, (sorted) =>
			tableOrder(kindOfRecord, sorted, lists, tableSort, progresses),
		);
	}, [column, records, initial.id, view, epicNames, inContent, lists, progresses]);

	useEffect(() => {
		const url = new URL(window.location.href);
		if (!url.searchParams.has("error")) return;
		url.searchParams.delete("error");
		router.replace(`${url.pathname}${url.search}`, { scroll: false });
	}, [router, failure]);

	useEffect(() => {
		if (failure) setError(failure);
	}, [failure]);

	function go(href: string) {
		if (confirmDiscard()) router.push(href);
	}

	function save(change: Partial<Card>, request: () => Promise<Result>, label: string) {
		const before = record;
		setRecord((current) => ({ ...current, ...change }));
		setError("");
		setToast(null);
		startTransition(async () => {
			const result = await request();
			if (result.error) {
				setRecord(before);
				const refused = projectRefusal(result.error);
				if (refused) {
					setClosing({ id: before.id, name: before.name, ...refused });
					return;
				}
				setError(result.error);
				if (result.moved || result.archived) {
					router.replace(`/card/${result.moved ?? before.id}?error=${encodeURIComponent(result.error)}`);
				}
				return;
			}
			if (!result.record) return;
			setRecord(result.record);
			const shown = undoable(result.record.id, result.undo, withNewId(label, before.id, result.record.id), result.more);
			shown?.changes.push(...(result.closed ?? []));
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
			const [change, ...rest] = shown.changes;
			const result = await undoChange(change.id, { since: change.since, until: change.until });
			const failures = [];
			for (const other of rest) {
				const undone = await undoChange(other.id, { since: other.since, until: other.until });
				if (undone.error) failures.push(undone.error);
			}
			setUndoing(false);
			if (failures.length > 0) setError(`Could not undo: ${failures.join("; ")}`);
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

	function close(shown: Closing) {
		setClosing(null);
		save({ status: "Done" }, () => closeProject(shown.id), `Closed ${shown.id} and everything open in it`);
	}

	const handlers: Handlers = {
		onMove: (status) => save(movedTo(status), () => dropCard(record.id, status), `Moved ${record.id} to ${status}`),
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
				go(id.startsWith("EPIC-") ? `/epics?open=${id}` : `/card/${id}`);
				return true;
			},
		}),
		[lists.cards, lists.epics, router],
	);

	const kind = kindOf(record.id);
	const edits: Edits = {
		label: record.id,
		move: handlers.onMove,
		edit: handlers.onEdit,
		duplicate: kind ? duplicate : undefined,
		archive,
	};

	function archive() {
		if (!confirmDiscard()) return;
		setError("");
		setToast(null);
		startTransition(async () => {
			const result = await archiveOne(record.id);
			if (result.error) {
				setError(`Could not archive ${record.id}: ${result.error}`);
				return;
			}
			router.push(`/card/${record.id}`);
		});
	}

	function duplicate() {
		if (!confirmDiscard()) return;
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
				...(kind
					? []
					: [
							iconCommand(record, edits),
							{ id: "do:archive", group: record.id, label: "Archive", keywords: "remove delete hide", run: archive },
						]),
				{ id: "do:copy", group: record.id, label: "Copy id", hint: "Cmd/Ctrl+.", run: () => copy(false) },
				{ id: "do:link", group: record.id, label: "Copy link", run: () => copy(true) },
				{
					id: "go:board",
					group: "Board",
					label: "Show it on the board",
					run: () => go(homeOf(record.id)),
				},
				...themeCommands(),
				...cardCommands(
					lists.cards.filter((card) => card.id !== record.id),
					(id) => go(`/card/${id}`),
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
			go(`/card/${to.id}`);
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
			{record.icon && <span className="page-icon">{record.icon}</span>}
			<Title
				id={record.id}
				className="title-input"
				value={record.name}
				onCommit={(name) => handlers.onEdit("name", name, { name })}
			/>
			<p className="meta">
				<span>{record.id}</span>
				{record.type && <span>{record.type}</span>}
				{!kind && <span>{recordKindOf(record.id)}</span>}
				{record.status && <span>{record.status}</span>}
				{saving && <span className="saving">Saving…</span>}
				<span className="record-actions">
					{kind && (
						<button type="button" className="quiet" onClick={duplicate} title="Make a copy of it in the first column">
							Duplicate
						</button>
					)}
					<button
						type="button"
						className="quiet"
						onClick={archive}
						title="Take it off the board - bring it back from the Archive page"
					>
						Archive
					</button>
				</span>
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

			{members.length > 0 && (
				<section className="timeline members">
					<h3>
						{recordKindOf(record.id) === "project" ? "Epics and cards" : "Cards"}{" "}
						<span className="count">{members.length}</span>
					</h3>
					<ol>
						{members.map((member) => (
							<li key={member.id}>
								<span className={`dot phase-${phaseOf(member.status)}`} aria-hidden="true" />
								<Link href={`/card/${member.id}`}>{member.name}</Link>
								<span className="ident">{member.id}</span>
							</li>
						))}
					</ol>
				</section>
			)}

			<dl className="facts">
				{kind && (
					<>
						<dt>Claimed by</dt>
						<dd>{record.session ?? <span className="empty">nobody</span>}</dd>
						<dt>Cost</dt>
						<dd>
							{record.cost_usd != null ? `$${record.cost_usd}` : <span className="empty">-</span>}
							{record.tokens_k != null && ` · ${record.tokens_k}k tokens`}
						</dd>
					</>
				)}
				{progresses[record.id] && (
					<>
						<dt>Progress</dt>
						<dd>
							<ProgressMeter progress={progresses[record.id]} wide />
						</dd>
					</>
				)}
				{!kind && record.created && (
					<>
						<dt>Created</dt>
						<dd>
							<time dateTime={record.created} suppressHydrationWarning>
								{stampText(record.created)}
							</time>
						</dd>
					</>
				)}
				{attachments.length > 0 && (
					<>
						<dt>Attachments</dt>
						<dd className="attachments">
							{attachments.map((name) => (
								<a key={name} href={attachmentHref(record.id, name)} target="_blank" rel="noreferrer">
									{name}
								</a>
							))}
						</dd>
					</>
				)}
			</dl>
			{estimates && <EstimateFacts estimates={estimates} />}
			{kind && <Stages record={record} />}

			<MentionContext.Provider value={mentions}>
				<Content
					id={record.id}
					body={record.body}
					onRecord={setRecord}
					onSaved={(saved, span, label) => {
						const shown = undoable(saved.id, span, label ?? `Changed the content of ${saved.id}`);
						setToast(shown);
						if (saved.id !== initial.id) {
							carryTo(saved.id, shown);
							router.replace(`/card/${saved.id}`);
						}
					}}
				/>
			</MentionContext.Provider>
			<ActivitySection
				id={record.id}
				revision={record.updated}
				onRestored={(restored, span, label) => {
					setRecord(restored);
					const shown = undoable(restored.id, span, label);
					setToast(shown);
					if (restored.id !== initial.id) {
						carryTo(restored.id, shown);
						router.replace(`/card/${restored.id}`);
					} else router.refresh();
				}}
			/>
			{closing && (
				<ProjectDoneDialog
					closing={closing}
					busy={saving}
					onClose={() => close(closing)}
					onCancel={() => setClosing(null)}
				/>
			)}
			<UndoToast toast={toast} busy={undoing} onUndo={undo} onDismiss={() => setToast(null)} />
			{palette && <Palette start={palette} onClose={() => setPalette(null)} />}
		</article>
	);
}
