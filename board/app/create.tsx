"use client";

import { useEffect, useRef, useState } from "react";
import { type NewOptions, submitNew } from "@/app/actions";
import { EmojiPicker } from "@/app/emoji-picker";
import { recordOptions, SearchSelect } from "@/app/search-select";
import type { Lists } from "@/app/fields";
import { boardColumns, type Kind, TYPES } from "@/lib/shared";

export type Draft = { name: string; status: string } & NewOptions;

export function NewRecord({
	kind,
	lists,
	open,
	label,
	defaults,
	onOpenChange,
	onCreate,
}: {
	kind: Kind;
	lists: Lists;
	open: boolean;
	label?: string;
	defaults: { status: string; type?: string; epic?: string; project?: string };
	onOpenChange: (open: boolean) => void;
	onCreate: (draft: Draft) => Promise<string | null>;
}) {
	const openEpics = lists.epics.filter((other) => other.status !== "Epic Done");
	const openProjects = lists.projects.filter((other) => other.status !== "Done");
	const openEpic = (wanted?: string) => openEpics.find((other) => other.id === wanted)?.id ?? openEpics[0]?.id ?? "";
	const openProject = (wanted?: string) =>
		kind === "epic" ? (openProjects.find((other) => other.id === wanted)?.id ?? openProjects[0]?.id ?? "") : "";
	const [name, setName] = useState("");
	const [status, setStatus] = useState(defaults.status);
	const [type, setType] = useState(defaults.type ?? "Feature");
	const [epic, setEpic] = useState(openEpic(defaults.epic));
	const [project, setProject] = useState(openProject(defaults.project));
	const [timebox, setTimebox] = useState("60");
	const [icon, setIcon] = useState("");
	const [body, setBody] = useState("");
	const [busy, setBusy] = useState(false);
	const [error, setError] = useState("");
	const box = useRef<HTMLInputElement>(null);
	const columns = boardColumns(kind);

	useEffect(() => {
		if (!open) return;
		setStatus(defaults.status);
		setType(defaults.type ?? "Feature");
		setEpic((current) => openEpic(defaults.epic ?? current));
		setProject(openProject(defaults.project));
		setError("");
		box.current?.focus();
	}, [open, defaults.status, defaults.type, defaults.epic, defaults.project]);

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
	const inherited = epicProject
		? (lists.projects.find((other) => other.id === epicProject)?.name ?? epicProject)
		: null;

	function close() {
		onOpenChange(false);
	}

	function changed(set: (value: string) => void) {
		return (event: { target: { value: string } }) => {
			set(event.target.value);
			setError("");
		};
	}

	async function create() {
		if (busy) return;
		if (!name.trim()) {
			setError(`Give the ${kind} a name before creating it.`);
			box.current?.focus();
			return;
		}
		if (kind === "card" && !epic) {
			setError("Every card has an epic: choose one before creating it.");
			return;
		}
		if (kind === "epic" && !project) {
			setError("Every epic has a project: choose one before creating it.");
			return;
		}
		setBusy(true);
		setError("");
		const failure = await onCreate({
			name: name.trim(),
			status,
			type: kind === "card" ? type : undefined,
			epic: kind === "card" ? epic || undefined : undefined,
			project: kind === "epic" ? project || undefined : undefined,
			timeboxMins: kind === "card" && type === "Timebox" ? timebox.trim() || undefined : undefined,
			icon: icon || undefined,
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
		setTimebox("60");
		setIcon("");
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
				title={`New ${kind}`}
				aria-label={label ? `New ${kind}` : undefined}
				onClick={(event) => {
					event.preventDefault();
					onOpenChange(!open);
				}}
			>
				{label ?? `+ New ${kind}`}
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
				<span className="new-title">
					<EmojiPicker name="icon" value={icon} onPick={setIcon} />
					<input
						ref={box}
						name="name"
						className="new-name"
						aria-label="Name"
						placeholder={`${kind === "card" ? "Card" : "Epic"} name`}
						required
						value={name}
						disabled={busy}
						onChange={changed(setName)}
					/>
				</span>
				<div className="new-props">
					<select name="status" aria-label="Status" value={status} onChange={changed(setStatus)}>
						{columns.map((column) => (
							<option key={column}>{column}</option>
						))}
					</select>
					{kind === "card" && (
						<select name="type" aria-label="Type" value={type} onChange={changed(setType)}>
							{TYPES.map((option) => (
								<option key={option}>{option}</option>
							))}
						</select>
					)}
					{kind === "card" && type === "Timebox" && (
						<label className="new-timebox">
							<input
								name="timebox_mins"
								type="number"
								min={1}
								aria-label="Timebox (mins)"
								value={timebox}
								onChange={changed(setTimebox)}
							/>
							<span>min</span>
						</label>
					)}
					{kind === "card" && (
						<SearchSelect
							label="Epic"
							value={epic}
							options={recordOptions(lists.epics, "Epic Done")}
							onChange={(value) => changed(setEpic)({ target: { value } })}
						/>
					)}
					{kind === "card" ? (
						<span className="new-project" aria-label="Project" title="A card's project is its epic's">
							{inherited ?? "No project"}
						</span>
					) : (
						<SearchSelect
							label="Project"
							value={project}
							options={recordOptions(lists.projects, "Done")}
							onChange={(value) => changed(setProject)({ target: { value } })}
						/>
					)}
				</div>
				<textarea
					name="body"
					className="new-body"
					aria-label="Content"
					placeholder="Content, in markdown (optional)"
					rows={6}
					value={body}
					disabled={busy}
					onChange={changed(setBody)}
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
