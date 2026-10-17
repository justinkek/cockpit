"use client";

import { useEffect, useRef, useState } from "react";
import { useKeys } from "@/app/keys";

export type ViewDialogAsk = { mode: "save"; name: string } | { mode: "delete"; name: string };

export function ViewDialog({
	ask,
	existing,
	onSave,
	onDelete,
	onCancel,
}: {
	ask: ViewDialogAsk;
	existing: string[];
	onSave: (name: string) => void;
	onDelete: (name: string) => void;
	onCancel: () => void;
}) {
	const [name, setName] = useState(ask.name);
	const [replacing, setReplacing] = useState<string | null>(null);
	const field = useRef<HTMLInputElement>(null);
	const confirm = useRef<HTMLButtonElement>(null);
	const asking = ask.mode === "delete" || replacing !== null;

	useEffect(() => {
		if (asking) confirm.current?.focus();
		else {
			field.current?.focus();
			field.current?.select();
		}
	}, [asking]);

	useKeys((event) => {
		if (event.key !== "Escape") return;
		event.preventDefault();
		onCancel();
	});

	function submit() {
		if (ask.mode === "delete") return onDelete(ask.name);
		if (replacing !== null) return onSave(replacing);
		const typed = name.trim();
		if (!typed) return;
		if (existing.includes(typed)) setReplacing(typed);
		else onSave(typed);
	}

	const title =
		ask.mode === "delete"
			? `Delete the saved view ${ask.name}?`
			: replacing !== null
				? `Replace the saved view ${replacing}?`
				: "Save this view";

	return (
		<div
			className="overlay"
			role="presentation"
			onMouseDown={(event) => event.target === event.currentTarget && onCancel()}
		>
			<div
				className="dialog view-dialog"
				role={asking ? "alertdialog" : "dialog"}
				aria-modal="true"
				aria-label={title}
				tabIndex={-1}
			>
				<header className="dialog-head">
					<h2>{title}</h2>
				</header>
				<form
					onSubmit={(event) => {
						event.preventDefault();
						submit();
					}}
				>
					{ask.mode === "delete" ? (
						<p>The filters shown now stay as they are.</p>
					) : replacing !== null ? (
						<p>A view called {replacing} is already saved. Replacing it keeps the filters, grouping, sort and layout shown now under that name.</p>
					) : (
						<label>
							<span>Name the filters, grouping, sort and layout</span>
							<input ref={field} value={name} onChange={(event) => setName(event.target.value)} aria-label="View name" />
						</label>
					)}
					<footer className="view-dialog-actions">
						<span className="spacer" />
						<button type="button" className="quiet" onClick={onCancel}>
							Cancel
						</button>
						<button
							ref={confirm}
							type="submit"
							className={ask.mode === "delete" ? "danger" : undefined}
							disabled={!asking && !name.trim()}
						>
							{ask.mode === "delete" ? "Delete" : replacing !== null ? "Replace" : "Save"}
						</button>
					</footer>
				</form>
			</div>
		</div>
	);
}
