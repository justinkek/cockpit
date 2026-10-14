"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { checkTodo, loadBody, loadComments, postComment, resolveThread } from "@/app/actions";
import { Markdown } from "@/app/markdown";
import type { Card, CommentThread } from "@/lib/shared";

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
	onRecord,
}: {
	id: string;
	body?: string;
	onRecord?: (record: Card) => void;
}) {
	const [body, setBody] = useState(given ?? "");
	const [threads, setThreads] = useState<CommentThread[]>([]);
	const [error, setError] = useState("");
	const [selection, setSelection] = useState<{ text: string; top: number; left: number } | null>(null);
	const [drafting, setDrafting] = useState<string | null>(null);
	const [focused, setFocused] = useState<string | null>(null);
	const [replying, setReplying] = useState<string | null>(null);
	const [, startTransition] = useTransition();
	const area = useRef<HTMLDivElement>(null);
	const checking = useRef(0);
	const bodyGiven = given !== undefined;

	useEffect(() => {
		if (given !== undefined && checking.current === 0) setBody(given);
	}, [given]);

	useEffect(() => {
		let live = true;
		setThreads([]);
		setSelection(null);
		setDrafting(null);
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

	function apply(request: Promise<{ threads?: CommentThread[]; error?: string }>) {
		startTransition(async () => {
			const result = await request;
			if (result.error) setError(result.error);
			else setError("");
			if (result.threads) setThreads(result.threads);
		});
	}

	function onMouseUp() {
		const picked = window.getSelection();
		const text = picked?.toString().trim() ?? "";
		if (!picked || !text || !area.current || picked.rangeCount === 0) {
			setSelection(null);
			return;
		}
		const range = picked.getRangeAt(0);
		if (!area.current.contains(range.commonAncestorContainer)) return;
		const box = range.getBoundingClientRect();
		const frame = area.current.getBoundingClientRect();
		setSelection({ text, top: box.top - frame.top - 34, left: Math.max(0, box.left - frame.left) });
	}

	const anchored = threads.filter((thread) => thread.anchor);
	const anchors = anchored.map((thread) => ({ text: thread.anchor as string, thread: thread.thread }));
	const orphaned = anchored.filter((thread) => !body.includes(thread.anchor as string));

	return (
		<section className="content">
			<div className="content-body" ref={area} onMouseUp={onMouseUp}>
				{body ? (
					<Markdown source={body} anchors={anchors} onAnchor={setFocused} onCheck={check} />
				) : (
					<p className="empty">No content.</p>
				)}
				{selection && !drafting && (
					<button
						type="button"
						className="selection-comment"
						style={{ top: selection.top, left: selection.left }}
						onMouseDown={(event) => event.preventDefault()}
						onClick={() => {
							if (!body.includes(selection.text)) {
								setError("Select text within one line to comment on it.");
								setSelection(null);
								return;
							}
							setDrafting(selection.text);
							setSelection(null);
						}}
					>
						Comment
					</button>
				)}
			</div>

			{error && <p className="notice error">{error}</p>}

			{drafting && (
				<div className="thread drafting">
					<blockquote className="quoted">{drafting}</blockquote>
					<Composer
						placeholder="Add a comment…"
						autoFocus
						onCancel={() => setDrafting(null)}
						onSubmit={(text) => {
							apply(postComment(id, text, drafting));
							setDrafting(null);
						}}
					/>
				</div>
			)}

			<section className="threads">
				<h3>Comments {threads.length > 0 && <span className="count">{threads.length}</span>}</h3>
				{threads.map((thread) => (
					<article
						key={thread.thread}
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
							<div key={comment.id} className="comment">
								<span className="comment-head">
									<strong>{comment.author}</strong>
									<time dateTime={comment.at}>{when(comment.at)}</time>
								</span>
								<p>{comment.text}</p>
							</div>
						))}
						{replying === thread.thread ? (
							<Composer
								placeholder="Reply…"
								autoFocus
								onCancel={() => setReplying(null)}
								onSubmit={(text) => {
									apply(postComment(id, text, undefined, thread.thread));
									setReplying(null);
								}}
							/>
						) : (
							<span className="thread-actions">
								<button type="button" className="quiet" onClick={() => setReplying(thread.thread)}>
									Reply
								</button>
								<button type="button" className="quiet" onClick={() => apply(resolveThread(id, thread.thread))}>
									Resolve
								</button>
							</span>
						)}
					</article>
				))}
				<Composer placeholder="Comment on the page…" onSubmit={(text) => apply(postComment(id, text))} />
			</section>
		</section>
	);
}
