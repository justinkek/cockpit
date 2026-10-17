"use client";

import { type MouseEvent as Click, useEffect, useLayoutEffect, useRef, useState, useTransition } from "react";
import {
	changeComment,
	loadBody,
	loadComments,
	postComment,
	removeComment,
	resolveThread,
	type Span,
	saveBody,
	submitCard,
} from "@/app/actions";
import { nameOf } from "@/app/code-block";
import { useHydrated } from "@/app/fields";
import { onBoardChange } from "@/app/live";
import { Markdown } from "@/app/markdown";
import { anchorFor } from "@/lib/anchor";
import { appendBlock, type BlockSpan, blockSource, blockSpans, replaceBlock } from "@/lib/blocks";
import { ago, type Card, type CommentThread } from "@/lib/shared";

type Threads = { threads?: CommentThread[]; me?: string | null; error?: string };

type Picked = { text: string; top: number; bottom: number; left: number };

const DISCARD = "Discard your changes to the content?";

const CONFLICT = /^<{7} [^\n]*\n[\s\S]*?^={7}\n[\s\S]*?^>{7} /m;

let unsavedDrafts = 0;

export function confirmDiscard() {
	return unsavedDrafts === 0 || window.confirm(DISCARD);
}

function numberOf(id: string) {
	return id.split("-").at(-1);
}

function leavesPage(event: MouseEvent) {
	if (event.defaultPrevented || event.button !== 0) return false;
	if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return false;
	const link = event.target instanceof Element ? event.target.closest("a[href]") : null;
	if (!(link instanceof HTMLAnchorElement) || link.hasAttribute("download")) return false;
	if (link.target && link.target !== "_self") return false;
	const to = new URL(link.href, window.location.href);
	if (to.origin !== window.location.origin) return false;
	return to.pathname !== window.location.pathname || to.search !== window.location.search;
}

function when(stamp: string) {
	const date = new Date(stamp);
	return Number.isNaN(date.getTime()) ? stamp : date.toLocaleString();
}

function Stamp({ at, edited }: { at: string; edited?: string }) {
	return (
		<>
			<time dateTime={at} title={when(at)} suppressHydrationWarning>
				{ago(at)}
			</time>
			{edited && (
				<span className="edited" title={`Edited ${when(edited)}`} suppressHydrationWarning>
					edited
				</span>
			)}
		</>
	);
}

type BlockEdit = { span: BlockSpan | null; base: string; original: string; text: string };

const ACTIVE = "a, button, input, select, textarea, label, summary, mark, .thread, .block-editor";

function blockIndex(body: string, span: BlockSpan) {
	return blockSpans(body).findIndex((other) => other.start === span.start && other.end === span.end);
}

function BlockEditor({
	text,
	onChange,
	onSave,
	onCancel,
}: {
	text: string;
	onChange: (text: string) => void;
	onSave: () => void;
	onCancel: () => void;
}) {
	const box = useRef<HTMLTextAreaElement>(null);
	useLayoutEffect(() => {
		const area = box.current;
		if (!area) return;
		area.style.height = "auto";
		area.style.height = `${area.scrollHeight + 2}px`;
	}, [text]);
	useEffect(() => {
		const area = box.current;
		if (!area) return;
		area.focus();
		area.setSelectionRange(area.value.length, area.value.length);
	}, []);
	return (
		<div className="body-editor block-editor">
			<textarea
				ref={box}
				aria-label="Block"
				value={text}
				rows={Math.max(1, text.split("\n").length)}
				spellCheck={!text.startsWith("```")}
				onChange={(event) => onChange(event.target.value)}
				onBlur={() => {
					if (document.hasFocus()) onSave();
				}}
				onKeyDown={(event) => {
					if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
						event.preventDefault();
						onSave();
					}
					if (event.key === "Escape") {
						event.preventDefault();
						event.stopPropagation();
						onCancel();
					}
				}}
			/>
			<span className="body-hint">Markdown · Cmd/Ctrl+Enter or click away to save · Esc to cancel · empty it to delete</span>
		</div>
	);
}

type Rewrite = { comment: string; thread: string; anchor: string | null; text: string };

function holds(threads: CommentThread[], comment: string) {
	return threads.some((thread) => thread.comments.some((other) => other.id === comment));
}

function Composer({
	placeholder,
	onSubmit,
	onCancel,
	autoFocus,
	initial = "",
	submitLabel = "Comment",
	onDraft,
}: {
	placeholder: string;
	onSubmit: (text: string) => void;
	onCancel?: () => void;
	autoFocus?: boolean;
	initial?: string;
	submitLabel?: string;
	onDraft?: (text: string) => void;
}) {
	const [text, setText] = useState(initial);
	const box = useRef<HTMLTextAreaElement>(null);
	useEffect(() => {
		if (autoFocus && box.current) box.current.setSelectionRange(initial.length, initial.length);
	}, [autoFocus, initial]);
	return (
		<form
			className="composer"
			onSubmit={(event) => {
				event.preventDefault();
				if (!text.trim()) return;
				onSubmit(text.trim());
				setText("");
			}}
		>
			<textarea
				ref={box}
				value={text}
				placeholder={placeholder}
				autoFocus={autoFocus}
				rows={2}
				onChange={(event) => {
					setText(event.target.value);
					onDraft?.(event.target.value);
				}}
				onKeyDown={(event) => {
					if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) event.currentTarget.form?.requestSubmit();
					if (event.key === "Escape") {
						event.stopPropagation();
						onCancel?.();
					}
				}}
			/>
			<span className="composer-actions">
				{onCancel && (
					<button type="button" className="quiet" onClick={onCancel}>
						Cancel
					</button>
				)}
				<button type="submit" disabled={!text.trim() || text.trim() === initial.trim()}>
					{submitLabel}
				</button>
			</span>
		</form>
	);
}

export function Content({
	id,
	body: given,
	revision,
	onEntity,
	onSaved,
}: {
	id: string;
	body?: string;
	revision?: string;
	onEntity?: (entity: Card) => void;
	onSaved?: (entity: Card, undo?: Span, label?: string) => void;
}) {
	const [body, setBody] = useState(given ?? "");
	const [threads, setThreads] = useState<CommentThread[]>([]);
	const [error, setError] = useState("");
	const [selection, setSelection] = useState<Picked | null>(null);
	const [drafting, setDrafting] = useState<Picked | null>(null);
	const [focused, setFocused] = useState<string | null>(null);
	const [replying, setReplying] = useState<string | null>(null);
	const [rewriting, setRewriting] = useState<Rewrite | null>(null);
	const [lost, setLost] = useState<Rewrite | null>(null);
	const rewriteDraft = useRef("");
	const rewritingNow = useRef(rewriting);
	rewritingNow.current = rewriting;
	const [me, setMe] = useState<string | null>(null);
	const [editing, setEditingState] = useState<BlockEdit | null>(null);
	const editingNow = useRef<BlockEdit | null>(null);
	const [target, setTarget] = useState<string | null>(null);
	const hydrated = useHydrated();
	const seenRevision = useRef(revision);
	const isEditing = editing !== null;
	const dirty = isEditing && editing.text !== editing.original;
	const shownBody = editing ? editing.base : body;
	const previous = useRef(id);
	const [, startTransition] = useTransition();
	const area = useRef<HTMLDivElement>(null);
	const list = useRef<HTMLElement>(null);
	const checking = useRef(0);
	const commenting = useRef(0);
	const shown = useRef(id);
	shown.current = id;
	const bodyGiven = given !== undefined;

	useEffect(() => {
		if (given !== undefined && checking.current === 0) setBody(given);
	}, [given]);

	useEffect(() => {
		let live = true;
		const renamed = previous.current !== id && numberOf(previous.current) === numberOf(id);
		previous.current = id;
		setThreads([]);
		setSelection(null);
		setDrafting(null);
		setReplying(null);
		setRewriting(null);
		setLost(null);
		setTarget(null);
		if (!renamed) {
			setError("");
			setEditing(null);
			setTarget(null);
		}
		if (!bodyGiven) {
			setBody("");
			loadBody(id).then((result) => {
				if (live && result.body !== undefined) setBody(result.body);
			});
		}
		loadComments(id).then((result) => {
			if (!live) return;
			if (result.threads) setThreads(result.threads);
			if (result.me !== undefined) setMe(result.me);
			if (result.error) setError(result.error);
		});
		return () => {
			live = false;
		};
	}, [id, bodyGiven]);

	function setEditing(next: BlockEdit | null) {
		editingNow.current = next;
		setEditingState(next);
	}

	function persist(before: string, edited: string, done: { label?: string; toast?: boolean; reopen?: BlockEdit } = {}) {
		setBody(edited);
		checking.current++;
		startTransition(async () => {
			const result = await saveBody(target ?? id, before, edited);
			checking.current--;
			if (result.error) {
				setBody(before);
				if (result.moved) setTarget(result.moved);
				setError(result.moved ? `${result.error} - save again to save your edit to ${result.moved}` : result.error);
				if (done.reopen && !editingNow.current) setEditing({ ...done.reopen, base: before });
				return;
			}
			setError("");
			setTarget(null);
			if (result.entity) {
				if (checking.current === 0) setBody(result.entity.body);
				onEntity?.(result.entity);
				if (done.toast) onSaved?.(result.entity, result.undo, done.label);
			}
		});
	}

	function check(line: number, finished: boolean) {
		const lines = shownBody.split("\n");
		const expected = lines[line];
		if (expected === undefined) return;
		lines[line] = expected.replace(/- \[( |x)\] /, finished ? "- [x] " : "- [ ] ");
		persist(shownBody, lines.join("\n"));
	}

	function changeLanguage(line: number, language: string) {
		const lines = shownBody.split("\n");
		const expected = lines[line];
		if (expected === undefined) return;
		lines[line] = expected.replace(/^(\s*)```.*$/, (_, indent: string) => `${indent}\`\`\`${language.trim()}`);
		persist(shownBody, lines.join("\n"), {
			toast: true,
			label: `Changed a code block of ${id} to ${nameOf(language)}`,
		});
	}

	function startBlock(block: number) {
		const span = blockSpans(shownBody)[block];
		if (!span) return;
		const original = blockSource(shownBody, span);
		setEditing({ span, base: shownBody, original, text: original });
	}

	function startAdding() {
		setEditing({ span: null, base: shownBody, original: "", text: "" });
	}

	function saveBlock() {
		const open = editingNow.current;
		if (!open) return;
		setEditing(null);
		if (open.text.replace(/\s+$/, "") === open.original.replace(/\s+$/, "")) return;
		const edited = open.span ? replaceBlock(open.base, open.span, open.text) : appendBlock(open.base, open.text);
		if (edited === open.base) return;
		const label = open.span && open.text.trim() === "" ? `Deleted a block of ${id}` : undefined;
		persist(open.base, edited, { toast: true, label, reopen: open });
	}

	function pick(event: Click<HTMLDivElement>) {
		if (!hydrated || event.defaultPrevented || event.button !== 0) return;
		if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
		const node = event.target;
		if (!(node instanceof Element) || !event.currentTarget.contains(node) || node.closest(ACTIVE)) return;
		if (window.getSelection()?.toString().trim()) return;
		const block = node.closest("[data-block]");
		if (block) startBlock(Number(block.getAttribute("data-block")));
	}

	useEffect(() => {
		if (bodyGiven || isEditing || seenRevision.current === revision) return;
		seenRevision.current = revision;
		let live = true;
		loadBody(id).then((result) => {
			if (live && result.body !== undefined) setBody(result.body);
		});
		return () => {
			live = false;
		};
	}, [revision, id, bodyGiven, isEditing]);

	useEffect(() => {
		if (!dirty) return;
		unsavedDrafts++;
		function warn(event: BeforeUnloadEvent) {
			event.preventDefault();
		}
		function guard(event: MouseEvent) {
			if (!leavesPage(event) || window.confirm(DISCARD)) return;
			event.preventDefault();
			event.stopPropagation();
		}
		window.addEventListener("beforeunload", warn);
		document.addEventListener("click", guard, true);
		return () => {
			unsavedDrafts--;
			window.removeEventListener("beforeunload", warn);
			document.removeEventListener("click", guard, true);
		};
	}, [dirty]);

	useEffect(
		() =>
			onBoardChange(() => {
				if (commenting.current > 0) return;
				const asked = id;
				loadComments(asked).then((result) => {
					if (shown.current !== asked || commenting.current > 0 || !result.threads) return;
					setThreads(result.threads);
					const open = rewritingNow.current;
					if (open && !holds(result.threads, open.comment)) {
						setRewriting(null);
						setLost({ ...open, text: rewriteDraft.current });
					}
				});
			}),
		[id],
	);

	function apply(
		optimistic: (current: CommentThread[]) => CommentThread[],
		request: () => Promise<Threads>,
		onFailed?: (fresh: CommentThread[]) => void,
	) {
		const before = threads;
		const asked = id;
		setThreads(optimistic(before));
		setError("");
		commenting.current++;
		startTransition(async () => {
			const result = await request().finally(() => {
				commenting.current--;
			});
			if (shown.current !== asked) return;
			if (result.error) {
				setError(result.error);
				const fresh = await loadComments(asked);
				if (shown.current !== asked) return;
				setThreads(fresh.threads ?? before);
				onFailed?.(fresh.threads ?? before);
				return;
			}
			if (result.threads) setThreads(result.threads);
			if (result.me !== undefined) setMe(result.me);
		});
	}

	function post(text: string, anchor?: string, reply?: string) {
		const pending = `pending-${Date.now()}`;
		const comment = { id: pending, author: "…", at: new Date().toISOString(), text };
		apply(
			(current) =>
				reply
					? current.map((thread) =>
							thread.thread === reply ? { ...thread, comments: [...thread.comments, comment] } : thread,
						)
					: [...current, { thread: pending, anchor: anchor ?? null, comments: [comment] }],
			() => postComment(id, text, anchor, reply),
		);
	}

	function resolve(thread: string, resolved: boolean) {
		apply(
			(current) => current.map((other) => (other.thread === thread ? { ...other, resolved } : other)),
			() => resolveThread(id, thread, resolved),
		);
	}

	function startRewrite(thread: CommentThread, comment: CommentThread["comments"][number]) {
		rewriteDraft.current = comment.text;
		setRewriting({ comment: comment.id, thread: thread.thread, anchor: thread.anchor, text: comment.text });
	}

	function rewrite(open: Rewrite, text: string) {
		const comment = open.comment;
		setRewriting(null);
		apply(
			(current) =>
				current.map((thread) => ({
					...thread,
					comments: thread.comments.map((other) =>
						other.id === comment ? { ...other, text, edited: new Date().toISOString() } : other,
					),
				})),
			() => changeComment(id, comment, text),
			(fresh) => {
				const kept = { ...open, text };
				rewriteDraft.current = text;
				if (holds(fresh, comment)) setRewriting(kept);
				else setLost(kept);
			},
		);
	}

	function repost(draft: Rewrite) {
		setLost(null);
		const thread = threads.find((other) => other.thread === draft.thread);
		if (thread) post(draft.text, undefined, thread.thread);
		else post(draft.text, draft.anchor ?? undefined);
	}

	function remove(comment: string) {
		if (!window.confirm("Delete this comment? This cannot be undone from here.")) return;
		apply(
			(current) =>
				current
					.map((thread) => ({ ...thread, comments: thread.comments.filter((other) => other.id !== comment) }))
					.filter((thread) => thread.comments.length > 0),
			() => removeComment(id, comment),
		);
	}

	useEffect(() => {
		let timer = 0;
		function read() {
			const picked = window.getSelection();
			const text = picked?.toString().trim() ?? "";
			const frame = area.current;
			if (!picked || !text || !frame || picked.rangeCount === 0) {
				setSelection(null);
				return;
			}
			const range = picked.getRangeAt(0);
			if (!frame.contains(range.commonAncestorContainer)) {
				setSelection(null);
				return;
			}
			const box = range.getBoundingClientRect();
			const bounds = frame.getBoundingClientRect();
			const below = window.matchMedia("(pointer: coarse)").matches;
			setSelection({
				text,
				top: (below ? box.bottom + 8 : box.top - 34) - bounds.top,
				bottom: box.bottom - bounds.top,
				left: Math.min(Math.max(0, box.left - bounds.left), Math.max(0, bounds.width - 90)),
			});
		}
		function onChange() {
			window.clearTimeout(timer);
			timer = window.setTimeout(read, 180);
		}
		document.addEventListener("selectionchange", onChange);
		return () => {
			window.clearTimeout(timer);
			document.removeEventListener("selectionchange", onChange);
		};
	}, []);

	function startDraft() {
		if (!selection) return;
		const anchor = anchorFor(selection.text, body);
		setSelection(null);
		if (!anchor) {
			setError("Select text within one line to comment on it.");
			return;
		}
		setError("");
		setDrafting({ ...selection, text: anchor });
		window.getSelection()?.removeAllRanges();
	}

	function reveal(thread: string) {
		setFocused(thread);
		list.current
			?.querySelector(`[data-thread="${CSS.escape(thread)}"]`)
			?.scrollIntoView({ block: "nearest", behavior: "smooth" });
	}

	const open = threads.filter((thread) => !thread.resolved);
	const resolved = threads.filter((thread) => thread.resolved);
	const anchored = open.filter((thread) => thread.anchor);
	function renderComment(thread: CommentThread, comment: CommentThread["comments"][number]) {
		const pending = comment.id.startsWith("pending-");
		const mine = !pending && me !== null && comment.author === me;
		return (
			<div key={comment.id} className={`comment${pending ? " pending" : ""}`}>
				<span className="comment-head">
					<strong>{comment.author}</strong>
					<Stamp at={comment.at} edited={comment.edited} />
					{mine && rewriting?.comment !== comment.id && (
						<span className="comment-tools">
							<button type="button" className="quiet" onClick={() => startRewrite(thread, comment)}>
								Edit
							</button>
							<button type="button" className="quiet" onClick={() => remove(comment.id)}>
								Delete
							</button>
						</span>
					)}
				</span>
				{rewriting?.comment === comment.id ? (
					<Composer
						placeholder="Edit your comment…"
						autoFocus
						initial={rewriting.text}
						submitLabel="Save"
						onDraft={(text) => {
							rewriteDraft.current = text;
						}}
						onCancel={() => setRewriting(null)}
						onSubmit={(text) => rewrite(rewriting, text)}
					/>
				) : (
					<Markdown source={comment.text} />
				)}
			</div>
		);
	}

	const blockEditor = editing && (
		<BlockEditor
			text={editing.text}
			onChange={(text) => {
				const open = editingNow.current;
				if (open) setEditing({ ...open, text });
			}}
			onSave={saveBlock}
			onCancel={() => setEditing(null)}
		/>
	);

	const anchors = anchored.map((thread) => ({ text: thread.anchor as string, thread: thread.thread }));
	const orphaned = anchored.filter((thread) => !body.includes(thread.anchor as string));

	return (
		<section className="content">
			{!hydrated ? (
				<details className="content-head body-fallback">
					<summary>Edit content</summary>
					<form action={submitCard} className="body-editor">
						<input type="hidden" name="id" value={id} />
						<input type="hidden" name="op" value="set" />
						<input type="hidden" name="field" value="body" />
						<input type="hidden" name="base" value={body} />
						<textarea
							name="value"
							aria-label="Content"
							defaultValue={body}
							rows={Math.min(40, Math.max(8, body.split("\n").length + 1))}
						/>
						<span className="composer-actions">
							<button type="submit">Save</button>
						</span>
					</form>
				</details>
			) : null}
			<div className="content-body" ref={area} onClick={pick}>
				{shownBody ? (
					<Markdown
						source={shownBody}
						anchors={anchors}
						onAnchor={reveal}
						onCheck={check}
						onLanguage={changeLanguage}
						editable={hydrated}
						editing={editing?.span ? { block: blockIndex(shownBody, editing.span), node: blockEditor } : undefined}
					/>
				) : (
					!editing && <p className="empty">No content.</p>
				)}
				{editing && !editing.span && blockEditor}
				{selection && !drafting && (
					<button
						type="button"
						className="selection-comment"
						style={{ top: selection.top, left: selection.left }}
						onPointerDown={(event) => event.preventDefault()}
						onMouseDown={(event) => event.preventDefault()}
						onClick={startDraft}
					>
						Comment
					</button>
				)}
				{drafting && (
					<div className="thread drafting" style={{ top: drafting.bottom + 8 }}>
						<blockquote className="quoted">{drafting.text}</blockquote>
						<Composer
							placeholder="Add a comment…"
							autoFocus
							onCancel={() => setDrafting(null)}
							onSubmit={(text) => {
								post(text, drafting.text);
								setDrafting(null);
							}}
						/>
					</div>
				)}
			</div>
			{hydrated && !editing && (
				<button type="button" className="quiet add-block" onClick={startAdding}>
					+ Add a block
				</button>
			)}

			{error && <p className="notice error">{error}</p>}
			{editing === null && CONFLICT.test(body) && (
				<p className="notice error conflict">
					Two edits changed the same lines of this content at once, so both versions are kept, the one saved last
					between the &lt;&lt;&lt;&lt;&lt;&lt;&lt; your edit and ======= lines and the one already there between =======
					and &gt;&gt;&gt;&gt;&gt;&gt;&gt; on the board now. Click the block holding them to keep the one you want and
					take out the marker lines.
				</p>
			)}
			{lost && (
				<div className="notice error lost-draft">
					<p>The comment you were editing was deleted, so your edit could not be saved. Here is what you wrote:</p>
					<blockquote className="quoted">{lost.text}</blockquote>
					<span className="composer-actions">
						<button type="button" className="quiet" onClick={() => setLost(null)}>
							Discard
						</button>
						<button type="button" onClick={() => repost(lost)}>
							Post as a new comment
						</button>
					</span>
				</div>
			)}

			<section className="threads" ref={list}>
				<h3>Comments {open.length > 0 && <span className="count">{open.length}</span>}</h3>
				{open.map((thread) => (
					<article
						key={thread.thread}
						data-thread={thread.thread}
						className={`thread${focused === thread.thread ? " focused" : ""}`}
						onMouseEnter={() => setFocused(thread.thread)}
						onMouseLeave={() => setFocused(null)}
					>
						{thread.anchor && (
							<blockquote className={`quoted${orphaned.includes(thread) ? " orphaned" : ""}`}>
								{thread.anchor}
							</blockquote>
						)}
						{thread.comments.map((comment) => renderComment(thread, comment))}
						{replying === thread.thread ? (
							<Composer
								placeholder="Reply…"
								autoFocus
								onCancel={() => setReplying(null)}
								onSubmit={(text) => {
									post(text, undefined, thread.thread);
									setReplying(null);
								}}
							/>
						) : (
							<span className="thread-actions">
								<button
									type="button"
									className="quiet"
									disabled={thread.thread.startsWith("pending-")}
									onClick={() => setReplying(thread.thread)}
								>
									Reply
								</button>
								<button
									type="button"
									className="quiet"
									disabled={thread.thread.startsWith("pending-")}
									onClick={() => resolve(thread.thread, true)}
								>
									Resolve
								</button>
							</span>
						)}
					</article>
				))}
				<Composer placeholder="Comment on the page…" onSubmit={(text) => post(text)} />
				{resolved.length > 0 && (
					<details className="resolved-threads">
						<summary>
							Resolved <span className="count">{resolved.length}</span>
						</summary>
						{resolved.map((thread) => (
							<article key={thread.thread} data-thread={thread.thread} className="thread resolved">
								{thread.anchor && <blockquote className="quoted">{thread.anchor}</blockquote>}
								{thread.comments.map((comment) => renderComment(thread, comment))}
								<span className="thread-actions">
									<button type="button" className="quiet" onClick={() => resolve(thread.thread, false)}>
										Reopen
									</button>
								</span>
							</article>
						))}
					</details>
				)}
			</section>
		</section>
	);
}
