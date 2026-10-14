"use client";

import { type ReactNode, useEffect, useRef, useState } from "react";
import { useFormStatus } from "react-dom";
import { submitRecord } from "@/app/actions";
import { PROJECT_STATUSES } from "@/lib/shared";

type Other = "project" | "sprint" | "reference";

function Submit({ kind }: { kind: Other }) {
	const { pending } = useFormStatus();
	return (
		<button type="submit" disabled={pending}>
			{pending ? "Creating…" : `Create ${kind}`}
		</button>
	);
}

function props(kind: Other): ReactNode {
	if (kind === "project") {
		return (
			<>
				<select name="status" aria-label="Status" defaultValue="Not started">
					{PROJECT_STATUSES.map((status) => (
						<option key={status}>{status}</option>
					))}
				</select>
				<input name="priority" type="number" min={0} aria-label="Priority" placeholder="Priority" />
				<input name="repo" type="url" aria-label="Repo" placeholder="Repo URL" />
			</>
		);
	}
	return null;
}

export function NewOther({ kind, label = `+ New ${kind}` }: { kind: Other; label?: string }) {
	const [open, setOpen] = useState(false);
	const frame = useRef<HTMLDetailsElement>(null);
	const name = useRef<HTMLInputElement>(null);

	useEffect(() => {
		if (!open) return;
		name.current?.focus();
		function onDown(event: PointerEvent) {
			if (name.current?.value.trim()) return;
			if (frame.current && !frame.current.contains(event.target as Node)) setOpen(false);
		}
		document.addEventListener("pointerdown", onDown);
		return () => document.removeEventListener("pointerdown", onDown);
	}, [open]);

	return (
		<details
			ref={frame}
			className="new-record"
			open={open}
			onToggle={(event) => {
				const opened = event.currentTarget.open;
				if (opened !== open) setOpen(opened);
			}}
		>
			<summary
				className="new-open"
				onClick={(event) => {
					event.preventDefault();
					setOpen(!open);
				}}
			>
				{label}
			</summary>
			<form
				className="new-panel"
				action={submitRecord}
				aria-label={`New ${kind}`}
				onKeyDown={(event) => {
					if (event.key === "Escape") {
						event.preventDefault();
						event.stopPropagation();
						setOpen(false);
					}
					if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
						event.preventDefault();
						event.currentTarget.requestSubmit();
					}
				}}
			>
				<input type="hidden" name="kind" value={kind} />
				<input
					ref={name}
					name="name"
					className="new-name"
					aria-label="Name"
					placeholder={`${kind[0].toUpperCase()}${kind.slice(1)} name`}
					required
				/>
				<div className="new-props">{props(kind)}</div>
				<span className="composer-actions">
					<button type="button" className="quiet" onClick={() => setOpen(false)}>
						Cancel
					</button>
					<Submit kind={kind} />
				</span>
			</form>
		</details>
	);
}
