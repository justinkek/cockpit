"use client";

import { useEffect, useRef, useState } from "react";
import { type NewOptions, submitNew } from "@/app/actions";
import type { Lists } from "@/app/fields";
import { boardColumns, type Kind, TYPES } from "@/lib/shared";

export type Draft = { name: string; status: string } & NewOptions;

export function NewRecord({
	kind,
	lists,
	open,
	defaults,
	onOpenChange,
	onCreate,
}: {
	kind: Kind;
	lists: Lists;
	open: boolean;
	defaults: { status: string; type?: string; epic?: string };
	onOpenChange: (open: boolean) => void;
	onCreate: (draft: Draft) => Promise<string | null>;
}) {
	const [name, setName] = useState("");
	const [status, setStatus] = useState(defaults.status);
	const [type, setType] = useState(defaults.type ?? "Feature");
	const [epic, setEpic] = useState(defaults.epic ?? "");
	const [project, setProject] = useState("");
	const [body, setBody] = useState("");
	const [busy, setBusy] = useState(false);
	const [error, setError] = useState("");
	const box = useRef<HTMLInputElement>(null);
	const columns = boardColumns(kind);

	useEffect(() => {
		if (!open) return;
		setStatus(defaults.status);
		setType(defaults.type ?? "Feature");
		setEpic(defaults.epic ?? "");
		setError("");
		box.current?.focus();
	}, [open, defaults.status, defaults.type, defaults.epic]);

	const frame = useRef<HTMLDetailsElement>(null);
	const empty = !name.trim() && !body.trim();

	useEffect(() => {
		if (!open || !empty) return;
		function onDown(event: PointerEvent) {
			if (frame.current && !frame.current.contains(event.target as Node)) onOpenChange(false);
		}
		document.addEventListener("pointerdown", onDown);
		return () => document.removeEventListener("pointerdown", onDown);
	}, [open, empty, onOpenChange]);

	const epicProject = epic ? lists.epics.find((other) => other.id === epic)?.project : null;
	const inherited = epicProject ? (lists.projects.find((other) => other.id === epicProject)?.name ?? epicProject) : null;

	function close() {
		onOpenChange(false);
	}

	async function create() {
		if (!name.trim() || busy) return;
		setBusy(true);
		setError("");
		const failure = await onCreate({
			name: name.trim(),
			status,
			type: kind === "card" ? type : undefined,
			epic: kind === "card" ? epic || undefined : undefined,
			project: project || undefined,
			body: body.trim() ? body : undefined,
		});
		setBusy(false);
		if (failure) {
			setError(failure);
			return;
		}
		setName("");
		setBody("");
		setProject("");
	}

	return (
		<details
			ref={frame}
			className="new-record"
			open={open}
			onToggle={(event) => {
				const opened = event.currentTarget.open;
				if (opened !== open) onOpenChange(opened);
			}}
		>
			<summary
				className="new-open"
				title={`New ${kind} (Shift+C)`}
				onClick={(event) => {
					event.preventDefault();
					onOpenChange(!open);
				}}
			>
				+ New {kind}
			</summary>
			<form
				className="new-panel"
				action={submitNew}
				aria-label={`New ${kind}`}
				onSubmit={(event) => {
					event.preventDefault();
					create();
				}}
				onKeyDown={(event) => {
					if (event.key === "Escape") {
						event.preventDefault();
						event.stopPropagation();
						close();
					}
					if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
						event.preventDefault();
						create();
					}
				}}
			>
				<input type="hidden" name="kind" value={kind} />
				<input
					ref={box}
					name="name"
					className="new-name"
					aria-label="Name"
					placeholder={`${kind === "card" ? "Card" : "Epic"} name`}
					required
					value={name}
					disabled={busy}
					onChange={(event) => setName(event.target.value)}
				/>
				<div className="new-props">
					<select name="status" aria-label="Status" value={status} onChange={(event) => setStatus(event.target.value)}>
						{columns.map((column) => (
							<option key={column}>{column}</option>
						))}
					</select>
					{kind === "card" && (
						<select name="type" aria-label="Type" value={type} onChange={(event) => setType(event.target.value)}>
							{TYPES.map((option) => (
								<option key={option}>{option}</option>
							))}
						</select>
					)}
					{kind === "card" && (
						<select name="epic" aria-label="Epic" value={epic} onChange={(event) => setEpic(event.target.value)}>
							<option value="">No epic</option>
							{lists.epics.map((option) => (
								<option key={option.id} value={option.id}>
									{option.name}
								</option>
							))}
						</select>
					)}
					<select
						name="project"
						aria-label="Project"
						value={project}
						onChange={(event) => setProject(event.target.value)}
					>
						<option value="">{inherited ? `${inherited} (from the epic)` : "No project"}</option>
						{lists.projects.map((option) => (
							<option key={option.id} value={option.id}>
								{option.name}
							</option>
						))}
					</select>
				</div>
				<textarea
					name="body"
					className="new-body"
					aria-label="Content"
					placeholder="Content, in markdown (optional)"
					rows={6}
					value={body}
					disabled={busy}
					onChange={(event) => setBody(event.target.value)}
				/>
				{error && (
					<p className="new-error" role="alert">
						{error}
					</p>
				)}
				<span className="composer-actions">
					<button type="button" className="quiet" onClick={close}>
						Cancel
					</button>
					<button type="submit" disabled={busy}>
						{busy ? "Creating…" : `Create ${kind}`}
					</button>
				</span>
			</form>
		</details>
	);
}
