"use client";

import { type ReactNode, startTransition, useActionState, useEffect, useRef, useState } from "react";
import { submitEntity } from "@/app/actions";
import { EmojiPicker } from "@/app/emoji-picker";
import { DOMAINS, FIBONACCI, PROJECT_STATUSES } from "@/lib/shared";

type Other = "project" | "sprint" | "reference";

function Submit({ kind, pending }: { kind: Other; pending: boolean }) {
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
				<input
					name="key"
					required
					pattern="[A-Za-z]{2,4}"
					maxLength={4}
					aria-label="Key"
					placeholder="Key, like COC"
					title="2 to 4 letters no other project has, numbering its tickets"
				/>
				<input name="priority" type="number" min={0} aria-label="Priority" placeholder="Priority" />
				<input name="repo" type="url" aria-label="Repo" placeholder="Repo URL" />
			</>
		);
	}
	if (kind === "sprint") {
		return (
			<>
				<label className="new-date">
					<span>Start</span>
					<input name="start" type="date" aria-label="Start" />
				</label>
				<label className="new-date">
					<span>End</span>
					<input name="end" type="date" aria-label="End" />
				</label>
				<input name="dev_days" type="number" min={0} step="any" aria-label="Dev days" placeholder="Dev days" />
				<input name="speed" type="number" min={0} step="any" aria-label="Speed" placeholder="Speed" />
			</>
		);
	}
	if (kind === "reference") {
		return (
			<>
				<select name="points" aria-label="Points" defaultValue="">
					<option value="">Points</option>
					{FIBONACCI.map((points) => (
						<option key={points}>{points}</option>
					))}
				</select>
				<select name="domain" aria-label="Domain" defaultValue="">
					<option value="">No domain</option>
					{DOMAINS.map((domain) => (
						<option key={domain}>{domain}</option>
					))}
				</select>
				<input name="stack" aria-label="Stack" placeholder="Stack" />
			</>
		);
	}
	return null;
}

export function NewOther({ kind, label = `+ New ${kind}` }: { kind: Other; label?: string }) {
	const [open, setOpen] = useState(false);
	const [icon, setIcon] = useState("");
	const [failure, create, pending] = useActionState(submitEntity, null);
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
			className="new-entity"
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
				aria-label={`New ${kind}`}
				onSubmit={(event) => {
					event.preventDefault();
					const form = new FormData(event.currentTarget);
					startTransition(() => create(form));
				}}
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
				<span className="new-title">
					<EmojiPicker name="icon" value={icon} onPick={setIcon} />
					<input
						ref={name}
						name="name"
						className="new-name"
						aria-label="Name"
						placeholder={`${kind[0].toUpperCase()}${kind.slice(1)} name`}
						required
					/>
				</span>
				<div className="new-props">{props(kind)}</div>
				{failure && !pending && (
					<p className="new-error" role="alert">
						{failure}
					</p>
				)}
				<span className="composer-actions">
					<button type="button" className="quiet" onClick={() => setOpen(false)}>
						Cancel
					</button>
					<Submit kind={kind} pending={pending} />
				</span>
			</form>
		</details>
	);
}
