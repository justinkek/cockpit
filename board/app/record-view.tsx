"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { type MouseEvent, type ReactNode, useEffect, useMemo, useState, useTransition } from "react";
import { ActivitySection } from "@/app/activity";
import {
	archiveOne,
	closeProject,
	dropCard,
	duplicateCard,
	editCard,
	findInContent,
	finishEpic,
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
import { askFinishedEpic, askMoveDone, finishedEpic, useConfirm } from "@/app/confirm";
import { type Closing, EpicDoneDialog, type Finishing, openTickets, ProjectDoneDialog } from "@/app/epic-done";
import { EstimateFacts } from "@/app/estimates";
import { Fields, type Handlers, Links, linkChange, Title } from "@/app/fields";
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
import { loadView, type Neighbours, neighboursIn, type View } from "@/app/view";
import type { RecordViewData } from "@/lib/record-view";
import {
	type Card,
	contentSearchFailed,
	fieldName,
	homeOf,
	kindOf,
	movedTo,
	type Named,
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

export type OverlayHost = {
	siblings?: { label: string; records: Named[] };
	onOpen: (id: string, replace?: boolean) => void;
	onClose: () => void;
	onChanged: () => void;
	onReload: () => void;
};

function siblingsOf(siblings: OverlayHost["siblings"], id: string): Neighbours {
	const index = siblings?.records.findIndex((record) => record.id === id) ?? -1;
	if (!siblings || index < 0) return null;
	const near = (record?: Named) => (record ? { id: record.id, name: record.name } : null);
	return {
		previous: near(siblings.records[index - 1]),
		next: near(siblings.records[index + 1]),
		position: index + 1,
		total: siblings.records.length,
	};
}

function plainClick(event: MouseEvent) {
	return event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey;
}

export function RecordView({
	data,
	failure,
	overlay,
}: {
	data: RecordViewData;
	failure?: string;
	overlay?: OverlayHost;
}) {
	const { record: initial, lists, column, records, attachments, progresses, estimates, members } = data;
	const router = useRouter();
	const [record, setRecord] = useState(initial);
	const [error, setError] = useState(failure ?? "");
	const [saving, startTransition] = useTransition();
	const [toast, setToast] = useState<Undoable | null>(null);
	const [undoing, setUndoing] = useState(false);
	const [palette, setPalette] = useState<Page | null>(null);
	const [closing, setClosing] = useState<Closing | null>(null);
	const [finishing, setFinishing] = useState<Finishing | null>(null);
	const [confirmDialog, ask] = useConfirm();

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
		if (overlay) return siblingsOf(overlay.siblings, initial.id);
		const kindOfRecord = kindOf(initial.id);
		const found = { names: epicNames, inContent };
		if (view?.layout !== "table" || !kindOfRecord) return neighboursIn(column, initial.id, view, found);
		const tableSort = view.tableSort;
		return neighboursIn(records, initial.id, view, found, (sorted) =>
			tableOrder(kindOfRecord, sorted, lists, tableSort, progresses),
		);
	}, [column, records, initial.id, view, epicNames, inContent, lists, progresses, overlay?.siblings]);

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

	function to(id: string, replace = false) {
		if (overlay) overlay.onOpen(id, replace);
		else if (replace) router.replace(`/card/${id}`);
		else go(`/card/${id}`);
	}

	function recordLink(id: string, children: ReactNode, rest: { title?: string; rel?: string } = {}) {
		return (
			<Link
				href={`/card/${id}`}
				{...rest}
				onClick={(event) => {
					if (!overlay || !plainClick(event)) return;
					event.preventDefault();
					to(id, rest.rel !== undefined);
				}}
			>
				{children}
			</Link>
		);
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
				setError(result.error);
				if (overlay && result.moved) overlay.onOpen(result.moved, true);
				else if (overlay && result.archived) overlay.onReload();
				else if (result.moved || result.archived) {
					router.replace(`/card/${result.moved ?? before.id}?error=${encodeURIComponent(result.error)}`);
				}
				return;
			}
			if (!result.record) return;
			setRecord(result.record);
			const shown = undoable(result.record.id, result.undo, withNewId(label, before.id, result.record.id), result.more);
			shown?.changes.push(...(result.closed ?? []));
			setToast(shown);
			overlay?.onChanged();
			if (result.record.id !== before.id) {
				carryTo(result.record.id, shown);
				to(result.record.id, true);
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
			if (result.record.id !== change.id) to(result.record.id, true);
			else if (overlay) overlay.onChanged();
			else router.refresh();
		});
	}

	function close(shown: Closing) {
		setClosing(null);
		save({ status: "Done" }, () => closeProject(shown.id), `Closed ${shown.id} and everything open in it`);
	}

	function finish(shown: Finishing) {
		setFinishing(null);
		setError("");
		setToast(null);
		startTransition(async () => {
			const result = await finishEpic(
				shown.id,
				shown.open.map((card) => card.id),
			);
			if (result.record) setRecord(result.record);
			if (result.errors.length > 0) setError(result.errors.join("; "));
			const count = shown.open.length === 1 ? "1 open ticket" : `${shown.open.length} open tickets`;
			if (result.undo.length > 0)
				setToast(
					toastOf(
						`Deprioritised ${count} of ${shown.id}${result.record ? " and moved it to Epic Done" : ""}`,
						result.undo,
					),
				);
			if (overlay) overlay.onChanged();
			else router.refresh();
		});
	}

	function finishAnyway(shown: Finishing) {
		setFinishing(null);
		save(movedTo("Epic Done"), () => dropCard(shown.id, "Epic Done"), `Moved ${shown.id} to Epic Done`);
	}

	function closeAnyway(shown: Closing) {
		setClosing(null);
		save({ status: "Done" }, () => editCard(shown.id, "status", "Done"), `Marked ${shown.id} Done`);
	}

	function openWork() {
		const epics = members.filter((member) => member.id.startsWith("EPIC-") && member.status !== "Epic Done").length;
		const tickets = members.filter(
			(member) => !member.id.startsWith("EPIC-") && member.status !== "Done" && member.status !== "Deprioritised",
		).length;
		return { epics, tickets };
	}

	const handlers: Handlers = {
		onMove: async (status) => {
			const leavingDone = kindOf(record.id) === "card" && record.status === "Done" && status !== "Done";
			if (leavingDone && !(await askMoveDone(ask))) return;
			const open = kindOf(record.id) === "epic" && status === "Epic Done" && record.status !== status;
			const tickets = open ? openTickets(members) : [];
			if (tickets.length > 0) return setFinishing({ id: record.id, name: record.name, open: tickets });
			save(movedTo(status), () => dropCard(record.id, status), `Moved ${record.id} to ${status}`);
		},
		onEdit: async (field, value, change) => {
			const joining = kindOf(record.id) === "card" && field === "epic" && value !== record.epic;
			const finished = joining ? finishedEpic(lists.epics, value) : undefined;
			if (finished && !(await askFinishedEpic(ask, finished))) return;
			if (recordKindOf(record.id) === "project" && field === "status" && value === "Done" && record.status !== "Done") {
				const open = openWork();
				if (open.epics > 0 || open.tickets > 0) return setClosing({ id: record.id, name: record.name, ...open });
			}
			save(change, () => editCard(record.id, field, value), `Changed the ${fieldName(field)} of ${record.id}`);
		},
		onLink: (parent, child, linked) =>
			save(
				linkChange(record, parent, child, linked),
				() => linkCards(record.id, parent, child, linked),
				linked ? `Linked ${parent} to ${child}` : `Unlinked ${parent} from ${child}`,
			),
		onOpen: overlay ? (id) => to(id) : undefined,
	};

	const mentions = useMemo<Mentions>(
		() => ({
			nameOf: mentionNames([...lists.cards, ...lists.epics], lists.aliases),
			onOpen: (id) => {
				if (overlay) to(id);
				else go(id.startsWith("EPIC-") ? `/epics?open=${id}` : `/card/${id}`);
				return true;
			},
		}),
		[lists.cards, lists.epics, lists.aliases, router, overlay],
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
			if (overlay) {
				overlay.onChanged();
				overlay.onReload();
			} else router.push(`/card/${record.id}`);
		});
	}

	async function duplicate() {
		if (!confirmDiscard()) return;
		const finished = kindOf(record.id) === "card" ? finishedEpic(lists.epics, record.epic) : undefined;
		if (finished && !(await askFinishedEpic(ask, finished))) return;
		setError("");
		startTransition(async () => {
			const result = await duplicateCard(record.id);
			if (!result.record) {
				setError(result.error ?? "board-card made nothing");
				return;
			}
			carryTo(result.record.id, toastOf(`Duplicated ${record.id} as ${result.record.id}`));
			overlay?.onChanged();
			if (overlay) overlay.onOpen(result.record.id);
			else router.push(`/card/${result.record.id}`);
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
				...(overlay
					? [{ id: "do:page", group: record.id, label: "Open as page", run: () => go(`/card/${record.id}`) }]
					: []),
				{
					id: "go:board",
					group: "Board",
					label: "Show it on the board",
					run: () => go(homeOf(record.id)),
				},
				...themeCommands(),
				...cardCommands(
					lists.cards.filter((card) => card.id !== record.id),
					(id) => to(id),
				),
			],
		};
	}

	useKeys((event) => {
		if (palette || closing || finishing || event.defaultPrevented) return;
		const command = event.metaKey || event.ctrlKey;
		const typing = typingIn(event.target);
		const arrow = event.key === "ArrowDown" || event.key === "ArrowUp";
		if (overlay && event.key === "Escape" && !typing) {
			event.preventDefault();
			overlay.onClose();
		} else if (overlay && arrow && !command && !event.altKey && !event.shiftKey && !typing) {
			const next = event.key === "ArrowDown" ? neighbours?.next : neighbours?.previous;
			event.preventDefault();
			if (next) overlay.onOpen(next.id, true);
		} else if (command && !event.shiftKey && event.key.toLowerCase() === "k") {
			event.preventDefault();
			setPalette(rootPage());
		} else if (command && !typing && (event.code === "Period" || event.key === "." || event.key === ">")) {
			event.preventDefault();
			copy(event.shiftKey);
		} else if (!command && !event.altKey && !typing && (event.key === "j" || event.key === "k")) {
			const next = event.key === "j" ? neighbours?.next : neighbours?.previous;
			if (!next) return;
			event.preventDefault();
			to(next.id, Boolean(overlay));
		} else if (!command && !event.altKey && !typing && kind && (event.key === "s" || event.key === "e")) {
			if (event.key === "e" && kind !== "card") return;
			event.preventDefault();
			setPalette(event.key === "s" ? movePage(kind, record.status, edits) : epicPage(lists, record.epic, edits));
		}
	});

	return (
		<article className="stub">
			{neighbours && (
				<nav className="neighbours" aria-label={`Records in ${overlay?.siblings?.label ?? record.status}`}>
					{neighbours.previous ? (
						recordLink(neighbours.previous.id, `‹ ${neighbours.previous.id}`, {
							title: `Previous: ${neighbours.previous.name} (${overlay ? "Up" : "k"})`,
							rel: "prev",
						})
					) : (
						<span className="empty">‹</span>
					)}
					<span className="neighbours-at">
						{neighbours.position} of {neighbours.total} in {overlay?.siblings?.label ?? record.status}
					</span>
					{neighbours.next ? (
						recordLink(neighbours.next.id, `${neighbours.next.id} ›`, {
							title: `Next: ${neighbours.next.name} (${overlay ? "Down" : "j"})`,
							rel: "next",
						})
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
					<button type="button" className="quiet" onClick={() => copy(true)} title="Copy link (Cmd/Ctrl+Shift+.)">
						Copy link
					</button>
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
						{recordKindOf(record.id) === "project" ? "Epics and tickets" : "Tickets"}{" "}
						<span className="count">{members.length}</span>
					</h3>
					<ol>
						{members.map((member) => (
							<li key={member.id}>
								<span className={`dot phase-${phaseOf(member.status)}`} aria-hidden="true" />
								{recordLink(member.id, member.name)}
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
						overlay?.onChanged();
						if (saved.id !== initial.id) {
							carryTo(saved.id, shown);
							to(saved.id, true);
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
						to(restored.id, true);
					} else if (overlay) overlay.onChanged();
					else router.refresh();
				}}
			/>
			{closing && (
				<ProjectDoneDialog
					closing={closing}
					busy={saving}
					onClose={() => close(closing)}
					onAnyway={() => closeAnyway(closing)}
					onCancel={() => setClosing(null)}
				/>
			)}
			{finishing && (
				<EpicDoneDialog
					finishing={finishing}
					busy={saving}
					onDeprioritise={() => finish(finishing)}
					onAnyway={() => finishAnyway(finishing)}
					onCancel={() => setFinishing(null)}
				/>
			)}
			{confirmDialog}
			<UndoToast toast={toast} busy={undoing} onUndo={undo} onDismiss={() => setToast(null)} />
			{palette && <Palette start={palette} onClose={() => setPalette(null)} />}
		</article>
	);
}
