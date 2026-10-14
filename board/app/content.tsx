"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import {
	checkTodo,
	loadBody,
	loadComments,
	postComment,
	resolveThread,
	type Span,
	saveBody,
	submitCard,
} from "@/app/actions";
import { useHydrated } from "@/app/fields";
import { onBoardChange } from "@/app/live";
import { Markdown } from "@/app/markdown";
import { anchorFor } from "@/lib/anchor";
import type { Card, CommentThread } from "@/lib/shared";

type Threads = { threads?: CommentThread[]; error?: string };

type Picked = { text: string; top: number; bottom: number; left: number };

const DISCARD = "Discard your changes to the content?";

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

function Composer({
	placeholder,
	onSubmit,
	onCancel,
	autoFocus,
}: {
	placeholder: string;
	onSubmit: (text: string) => void;
	onCancel?: () => void;
	autoFocus?: boolean;
}) {
	const [text, setText] = useState("");
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
				value={text}
				placeholder={placeholder}
				autoFocus={autoFocus}
				rows={2}
				onChange={(event) => setText(event.target.value)}
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
				<button type="submit" disabled={!text.trim()}>
					Comment
				</button>
			</span>
		</form>
	);
}

export function Content({
	id,
	body: given,
	revision,
	onRecord,
	onSaved,
}: {
	id: string;
	body?: string;
	revision?: string;
	onRecord?: (record: Card) => void;
	onSaved?: (record: Card, undo?: Span) => void;
}) {
	const [body, setBody] = useState(given ?? "");
	const [threads, setThreads] = useState<CommentThread[]>([]);
	const [error, setError] = useState("");
	const [selection, setSelection] = useState<Picked | null>(null);
	const [drafting, setDrafting] = useState<Picked | null>(null);
	const [focused, setFocused] = useState<string | null>(null);
	const [replying, setReplying] = useState<string | null>(null);
	const [editing, setEditing] = useState<string | null>(null);
	const [base, setBase] = useState("");
	const [saving, setSaving] = useState(false);
	const [target, setTarget] = useState<string | null>(null);
	const hydrated = useHydrated();
	const seenRevision = useRef(revision);
	const isEditing = editing !== null;
	const dirty = isEditing && editing !== base;
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
		setTarget(null);
		if (!renamed) {
			setError("");
			setEditing(null);
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
			if (result.error) setError(result.error);
		});
		return () => {
			live = false;
		};
	}, [id, bodyGiven]);

	function check(line: number, done: boolean) {
		const lines = body.split("\n");
		const expected = lines[line];
		if (expected === undefined) return;
		const before = body;
		lines[line] = expected.replace(/- \[( |x)\] /, done ? "- [x] " : "- [ ] ");
		setBody(lines.join("\n"));
		checking.current++;
		startTransition(async () => {
			const result = await checkTodo(id, line, expected, done);
			checking.current--;
			if (result.error) {
				setBody(before);
				setError(result.error);
				return;
			}
			setError("");
			if (result.record) {
				if (checking.current === 0) setBody(result.record.body);
				onRecord?.(result.record);
			}
		});
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

	function startEditing() {
		setBase(body);
		setEditing(body);
		setError("");
	}

	function stopEditing() {
		if (dirty && !window.confirm(DISCARD)) return;
		setEditing(null);
		setError("");
	}

	function save(text: string) {
		if (saving) return;
		const expected = base;
		setSaving(true);
		startTransition(async () => {
			const result = await saveBody(target ?? id, expected, text);
			setSaving(false);
			if (result.error) {
				if (result.moved) setTarget(result.moved);
				setError(
					result.moved ? `${result.error} - press Save again to save your draft to ${result.moved}` : result.error,
				);
				if (result.body !== undefined) {
					setBody(result.body);
					setBase(result.body);
				}
				return;
			}
			setError("");
			setEditing(null);
			setTarget(null);
			if (result.record) {
				setBody(result.record.body);
				onRecord?.(result.record);
				onSaved?.(result.record, result.undo);
			}
		});
	}

	useEffect(
		() =>
			onBoardChange(() => {
				if (commenting.current > 0) return;
				const asked = id;
				loadComments(asked).then((result) => {
					if (shown.current === asked && commenting.current === 0 && result.threads) setThreads(result.threads);
				});
			}),
		[id],
	);

	function apply(optimistic: (current: CommentThread[]) => CommentThread[], request: () => Promise<Threads>) {
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
				if (shown.current === asked) setThreads(fresh.threads ?? before);
				return;
			}
			if (result.threads) setThreads(result.threads);
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

	function resolve(thread: string) {
		apply(
			(current) => current.filter((other) => other.thread !== thread),
			() => resolveThread(id, thread),
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

	const anchored = threads.filter((thread) => thread.anchor);
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
			) : editing === null ? (
				<div className="content-head">
					<button type="button" className="quiet" onClick={startEditing}>
						Edit content
					</button>
				</div>
			) : (
				<form
					className="body-editor"
					onSubmit={(event) => {
						event.preventDefault();
						save(editing);
					}}
				>
					<textarea
						aria-label="Content"
						value={editing}
						autoFocus
						readOnly={saving}
						rows={Math.min(40, Math.max(8, editing.split("\n").length + 1))}
						onChange={(event) => setEditing(event.target.value)}
						onKeyDown={(event) => {
							const command = event.metaKey || event.ctrlKey;
							if (command && (event.key === "Enter" || event.key.toLowerCase() === "s")) {
								event.preventDefault();
								event.currentTarget.form?.requestSubmit();
							}
							if (event.key === "Escape") {
								event.stopPropagation();
								stopEditing();
							}
						}}
					/>
					<span className="composer-actions">
						<span className="body-hint">Markdown · Cmd/Ctrl+S to save · Esc to cancel</span>
						<button type="button" className="quiet" onClick={stopEditing}>
							Cancel
						</button>
						<button type="submit" disabled={saving || !dirty}>
							{saving ? "Saving…" : "Save"}
						</button>
					</span>
				</form>
			)}
			<div className="content-body" ref={area} hidden={editing !== null}>
				{body ? (
					<Markdown source={body} anchors={anchors} onAnchor={reveal} onCheck={check} />
				) : (
					<p className="empty">
						No content.{" "}
						{hydrated && (
							<button type="button" className="quiet" onClick={startEditing}>
								Add some
							</button>
						)}
					</p>
				)}
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

			{error && <p className="notice error">{error}</p>}

			<section className="threads" ref={list}>
				<h3>Comments {threads.length > 0 && <span className="count">{threads.length}</span>}</h3>
				{threads.map((thread) => {
					const sending = thread.thread.startsWith("pending-");
					return (
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
							{thread.comments.map((comment) => (
								<div key={comment.id} className={`comment${comment.id.startsWith("pending-") ? " pending" : ""}`}>
									<span className="comment-head">
										<strong>{comment.author}</strong>
										<time dateTime={comment.at}>{when(comment.at)}</time>
									</span>
									<Markdown source={comment.text} />
								</div>
							))}
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
									<button type="button" className="quiet" disabled={sending} onClick={() => setReplying(thread.thread)}>
										Reply
									</button>
									<button type="button" className="quiet" disabled={sending} onClick={() => resolve(thread.thread)}>
										Resolve
									</button>
								</span>
							)}
						</article>
					);
				})}
				<Composer placeholder="Comment on the page…" onSubmit={(text) => post(text)} />
			</section>
		</section>
	);
}
