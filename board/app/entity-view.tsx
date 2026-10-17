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
	entityCommands,
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
import type { EntityViewData } from "@/lib/entity-view";
import {
	type Card,
	contentSearchFailed,
	fieldName,
	homeOf,
	kindOf,
	movedTo,
	type Named,
	phaseOf,
	entityKindOf,
} from "@/lib/shared";

type Result = {
	entity?: Card;
	error?: string;
	moved?: string;
	archived?: boolean;
	undo?: Span;
	more?: Change[];
	closed?: Change[];
};

export type OverlayHost = {
	siblings?: { label: string; entities: Named[] };
	onOpen: (id: string, replace?: boolean) => void;
	onClose: () => void;
	onChanged: () => void;
	onReload: () => void;
};

function siblingsOf(siblings: OverlayHost["siblings"], id: string): Neighbours {
	const index = siblings?.entities.findIndex((entity) => entity.id === id) ?? -1;
	if (!siblings || index < 0) return null;
	const near = (entity?: Named) => (entity ? { id: entity.id, name: entity.name } : null);
	return {
		previous: near(siblings.entities[index - 1]),
		next: near(siblings.entities[index + 1]),
		position: index + 1,
		total: siblings.entities.length,
	};
}

function plainClick(event: MouseEvent) {
	return event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey;
}

export function EntityView({
	data,
	failure,
	overlay,
}: {
	data: EntityViewData;
	failure?: string;
	overlay?: OverlayHost;
}) {
	const { entity: initial, lists, column, entities, attachments, progresses, estimates, members } = data;
	const router = useRouter();
	const [entity, setEntity] = useState(initial);
	const [error, setError] = useState(failure ?? "");
	const [saving, startTransition] = useTransition();
	const [toast, setToast] = useState<Undoable | null>(null);
	const [undoing, setUndoing] = useState(false);
	const [palette, setPalette] = useState<Page | null>(null);
	const [closing, setClosing] = useState<Closing | null>(null);
	const [finishing, setFinishing] = useState<Finishing | null>(null);
	const [confirmDialog, ask] = useConfirm();

	const [view, setView] = useState<View | null>(null);

	useEffect(() => setEntity(initial), [initial]);

	useEffect(() => {
		const handed = takeCarried(initial.id);
		if (handed) setToast(handed);
	}, [initial.id]);

	useEffect(() => {
		const kindOfEntity = kindOf(initial.id);
		if (kindOfEntity) setView(loadView(kindOfEntity));
	}, [initial.id]);

	const [found, setFound] = useState<{ query: string; ids: Set<string> } | null>(null);
	const query = view?.query.trim() ?? "";

	useEffect(() => {
		const kindOfEntity = kindOf(initial.id);
		if (query.length < 2 || !kindOfEntity) return;
		let live = true;
		findInContent(kindOfEntity, query).then((result) => {
			if (!live) return;
			if ("ids" in result) setFound({ query, ids: new Set(result.ids) });
			else setError(contentSearchFailed(kindOfEntity, result.error));
		});
		return () => {
			live = false;
		};
	}, [query, initial.id]);

	const epicNames = useMemo(() => Object.fromEntries(lists.epics.map((epic) => [epic.id, epic.name])), [lists.epics]);
	const inContent = found?.query === query ? found.ids : undefined;
	const neighbours = useMemo(() => {
		if (overlay) return siblingsOf(overlay.siblings, initial.id);
		const kindOfEntity = kindOf(initial.id);
		const found = { names: epicNames, inContent };
		if (view?.layout !== "table" || !kindOfEntity) return neighboursIn(column, initial.id, view, found);
		const tableSort = view.tableSort;
		return neighboursIn(entities, initial.id, view, found, (sorted) =>
			tableOrder(kindOfEntity, sorted, lists, tableSort, progresses),
		);
	}, [column, entities, initial.id, view, epicNames, inContent, lists, progresses, overlay?.siblings]);

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

	function entityLink(id: string, children: ReactNode, rest: { title?: string; rel?: string } = {}) {
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
		const before = entity;
		setEntity((current) => ({ ...current, ...change }));
		setError("");
		setToast(null);
		startTransition(async () => {
			const result = await request();
			if (result.error) {
				setEntity(before);
				setError(result.error);
				if (overlay && result.moved) overlay.onOpen(result.moved, true);
				else if (overlay && result.archived) overlay.onReload();
				else if (result.moved || result.archived) {
					router.replace(`/card/${result.moved ?? before.id}?error=${encodeURIComponent(result.error)}`);
				}
				return;
			}
			if (!result.entity) return;
			setEntity(result.entity);
			const shown = undoable(result.entity.id, result.undo, withNewId(label, before.id, result.entity.id), result.more);
			shown?.changes.push(...(result.closed ?? []));
			setToast(shown);
			overlay?.onChanged();
			if (result.entity.id !== before.id) {
				carryTo(result.entity.id, shown);
				to(result.entity.id, true);
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
			if (!result.entity) return;
			setEntity(result.entity);
			if (result.entity.id !== change.id) to(result.entity.id, true);
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
			if (result.entity) setEntity(result.entity);
			if (result.errors.length > 0) setError(result.errors.join("; "));
			const count = shown.open.length === 1 ? "1 open ticket" : `${shown.open.length} open tickets`;
			if (result.undo.length > 0)
				setToast(
					toastOf(
						`Deprioritised ${count} of ${shown.id}${result.entity ? " and moved it to Epic Done" : ""}`,
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
			const leavingDone = kindOf(entity.id) === "card" && entity.status === "Done" && status !== "Done";
			if (leavingDone && !(await askMoveDone(ask))) return;
			const open = kindOf(entity.id) === "epic" && status === "Epic Done" && entity.status !== status;
			const tickets = open ? openTickets(members) : [];
			if (tickets.length > 0) return setFinishing({ id: entity.id, name: entity.name, open: tickets });
			save(movedTo(status), () => dropCard(entity.id, status), `Moved ${entity.id} to ${status}`);
		},
		onEdit: async (field, value, change) => {
			const joining = kindOf(entity.id) === "card" && field === "epic" && value !== entity.epic;
			const finished = joining ? finishedEpic(lists.epics, value) : undefined;
			if (finished && !(await askFinishedEpic(ask, finished))) return;
			if (entityKindOf(entity.id) === "project" && field === "status" && value === "Done" && entity.status !== "Done") {
				const open = openWork();
				if (open.epics > 0 || open.tickets > 0) return setClosing({ id: entity.id, name: entity.name, ...open });
			}
			save(change, () => editCard(entity.id, field, value), `Changed the ${fieldName(field)} of ${entity.id}`);
		},
		onLink: (parent, child, linked) =>
			save(
				linkChange(entity, parent, child, linked),
				() => linkCards(entity.id, parent, child, linked),
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

	const kind = kindOf(entity.id);
	const edits: Edits = {
		label: entity.id,
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
			const result = await archiveOne(entity.id);
			if (result.error) {
				setError(`Could not archive ${entity.id}: ${result.error}`);
				return;
			}
			if (overlay) {
				overlay.onChanged();
				overlay.onReload();
			} else router.push(`/card/${entity.id}`);
		});
	}

	async function duplicate() {
		if (!confirmDiscard()) return;
		const finished = kindOf(entity.id) === "card" ? finishedEpic(lists.epics, entity.epic) : undefined;
		if (finished && !(await askFinishedEpic(ask, finished))) return;
		setError("");
		startTransition(async () => {
			const result = await duplicateCard(entity.id);
			if (!result.entity) {
				setError(result.error ?? "board-card made nothing");
				return;
			}
			carryTo(result.entity.id, toastOf(`Duplicated ${entity.id} as ${result.entity.id}`));
			overlay?.onChanged();
			if (overlay) overlay.onOpen(result.entity.id);
			else router.push(`/card/${result.entity.id}`);
		});
	}

	async function copy(asLink: boolean) {
		const copied = await copyText(asLink ? cardLink(entity.id) : entity.id);
		setToast(
			toastOf(copied ? `Copied ${asLink ? `the link to ${entity.id}` : entity.id}` : `Could not copy ${entity.id}`),
		);
	}

	function rootPage(): Page {
		return {
			title: "Command menu",
			root: true,
			items: [
				...entityCommands(kind, entity, lists, edits),
				...(kind
					? []
					: [
							iconCommand(entity, edits),
							{ id: "do:archive", group: entity.id, label: "Archive", keywords: "remove delete hide", run: archive },
						]),
				{ id: "do:copy", group: entity.id, label: "Copy id", hint: "Cmd/Ctrl+.", run: () => copy(false) },
				{ id: "do:link", group: entity.id, label: "Copy link", run: () => copy(true) },
				...(overlay
					? [{ id: "do:page", group: entity.id, label: "Open as page", run: () => go(`/card/${entity.id}`) }]
					: []),
				{
					id: "go:board",
					group: "Board",
					label: "Show it on the board",
					run: () => go(homeOf(entity.id)),
				},
				...themeCommands(),
				...cardCommands(
					lists.cards.filter((card) => card.id !== entity.id),
					(id) => to(id),
				),
			],
		};
	}

	useKeys((event) => {
		if (palette || closing || finishing || event.defaultPrevented) return;
		const command = event.metaKey || event.ctrlKey;
		const typing = typingIn(event.target);
		if (overlay && event.key === "Escape" && !typing) {
			event.preventDefault();
			overlay.onClose();
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
			setPalette(event.key === "s" ? movePage(kind, entity.status, edits) : epicPage(lists, entity.epic, edits));
		}
	});

	return (
		<article className="stub">
			{neighbours && (
				<nav className="neighbours" aria-label={`Entities in ${overlay?.siblings?.label ?? entity.status}`}>
					{neighbours.previous ? (
						entityLink(neighbours.previous.id, `‹ ${neighbours.previous.id}`, {
							title: `Previous: ${neighbours.previous.name} (k)`,
							rel: "prev",
						})
					) : (
						<span className="empty">‹</span>
					)}
					<span className="neighbours-at">
						{neighbours.position} of {neighbours.total} in {overlay?.siblings?.label ?? entity.status}
					</span>
					{neighbours.next ? (
						entityLink(neighbours.next.id, `${neighbours.next.id} ›`, {
							title: `Next: ${neighbours.next.name} (j)`,
							rel: "next",
						})
					) : (
						<span className="empty">›</span>
					)}
				</nav>
			)}
			{entity.icon && <span className="page-icon">{entity.icon}</span>}
			<Title
				id={entity.id}
				className="title-input"
				value={entity.name}
				onCommit={(name) => handlers.onEdit("name", name, { name })}
			/>
			<p className="meta">
				<span>{entity.id}</span>
				{entity.type && <span>{entity.type}</span>}
				{!kind && <span>{entityKindOf(entity.id)}</span>}
				{entity.status && <span>{entity.status}</span>}
				{saving && <span className="saving">Saving…</span>}
				<span className="entity-actions">
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

			<Fields entity={entity} lists={lists} handlers={handlers} />
			<Links entity={entity} lists={lists} handlers={handlers} />

			{members.length > 0 && (
				<section className="timeline members">
					<h3>
						{entityKindOf(entity.id) === "project" ? "Epics and tickets" : "Tickets"}{" "}
						<span className="count">{members.length}</span>
					</h3>
					<ol>
						{members.map((member) => (
							<li key={member.id}>
								<span className={`dot phase-${phaseOf(member.status)}`} aria-hidden="true" />
								{entityLink(member.id, member.name)}
								<span className="ident">{member.id}</span>
								{member.size && (
									<span className="member-size" title={member.size.title}>
										{member.size.text}
									</span>
								)}
							</li>
						))}
					</ol>
				</section>
			)}

			<dl className="facts">
				{kind && (
					<>
						<dt>Claimed by</dt>
						<dd>{entity.session ?? <span className="empty">nobody</span>}</dd>
						<dt>Cost</dt>
						<dd>
							{entity.cost_usd != null ? `$${entity.cost_usd}` : <span className="empty">-</span>}
							{entity.tokens_k != null && ` · ${entity.tokens_k}k tokens`}
						</dd>
					</>
				)}
				{progresses[entity.id] && (
					<>
						<dt>Progress</dt>
						<dd>
							<ProgressMeter progress={progresses[entity.id]} wide />
						</dd>
					</>
				)}
				{!kind && entity.created && (
					<>
						<dt>Created</dt>
						<dd>
							<time dateTime={entity.created} suppressHydrationWarning>
								{stampText(entity.created)}
							</time>
						</dd>
					</>
				)}
				{attachments.length > 0 && (
					<>
						<dt>Attachments</dt>
						<dd className="attachments">
							{attachments.map((name) => (
								<a key={name} href={attachmentHref(entity.id, name)} target="_blank" rel="noreferrer">
									{name}
								</a>
							))}
						</dd>
					</>
				)}
			</dl>
			{estimates && <EstimateFacts estimates={estimates} />}
			{kind && <Stages entity={entity} />}

			<MentionContext.Provider value={mentions}>
				<Content
					id={entity.id}
					body={entity.body}
					onEntity={setEntity}
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
				id={entity.id}
				revision={entity.updated}
				onRestored={(restored, span, label) => {
					setEntity(restored);
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
