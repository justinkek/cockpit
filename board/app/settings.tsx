"use client";

import Link from "next/link";
import { useEffect, useState, useTransition } from "react";
import { dropBreak, forgetSavedView, saveBreak, setBoardTracks } from "@/app/actions";
import { NOTIFY_CHANGED, type NotifyState, notifyState, setNotify } from "@/app/notify";
import { ThemePicker } from "@/app/theme";
import type { Break, SavedView } from "@/lib/shared";

type Project = { id: string; name: string; tracks?: number | null; status?: string | null };

type BreakDraft = { from: string; to: string; project: string; name: string };

const EMPTY: BreakDraft = { from: "", to: "", project: "", name: "" };

function tracksText(count: number) {
	return count === 1 ? "1 track" : `${count} tracks`;
}

function dayText(day: string) {
	const [year, month, date] = day.split("-").map(Number);
	return new Date(Date.UTC(year, month - 1, date)).toLocaleDateString("en-GB", {
		day: "numeric",
		month: "short",
		year: "numeric",
		timeZone: "UTC",
	});
}

function Planning({
	tracks: initialTracks,
	breaks: initialBreaks,
	projects,
}: {
	tracks: number;
	breaks: Break[];
	projects: Project[];
}) {
	const [tracks, setTracks] = useState(initialTracks);
	const [breaks, setBreaks] = useState(initialBreaks);
	const [draft, setDraft] = useState<BreakDraft>(EMPTY);
	const [error, setError] = useState<string | null>(null);
	const [busy, startTransition] = useTransition();
	useEffect(() => setTracks(initialTracks), [initialTracks]);
	useEffect(() => setBreaks(initialBreaks), [initialBreaks]);

	const allocated = projects.reduce((sum, project) => sum + (project.status === "Done" ? 0 : (project.tracks ?? 0)), 0);
	const nameOf = (id: string | null) => (id ? (projects.find((one) => one.id === id)?.name ?? id) : "Whole board");

	function changeTracks(count: number) {
		const before = tracks;
		if (count < 1 || count === before) return;
		if (count < allocated) {
			setError(
				`The projects' shares add up to ${allocated}, so the board needs at least ${tracksText(allocated)} - take a track from a project on the Plan page first.`,
			);
			return;
		}
		setError(null);
		setTracks(count);
		startTransition(async () => {
			const result = await setBoardTracks(count);
			if (result.error) {
				setTracks(before);
				setError(`The board's tracks: ${result.error}`);
				return;
			}
			if (result.tracks) setTracks(result.tracks);
		});
	}

	function addBreak() {
		setError(null);
		startTransition(async () => {
			const result = await saveBreak(draft.from, draft.to, draft.project, draft.name);
			if (result.error || !result.breaks) {
				setError(`Could not add the break: ${result.error ?? "board-card added nothing"}`);
				return;
			}
			setBreaks(result.breaks);
			setDraft(EMPTY);
		});
	}

	function removeBreak(id: string) {
		setError(null);
		startTransition(async () => {
			const result = await dropBreak(id);
			if (result.error || !result.breaks) {
				setError(`Could not remove the break: ${result.error ?? "board-card removed nothing"}`);
				return;
			}
			setBreaks(result.breaks);
		});
	}

	return (
		<section className="settings-section" id="planning" aria-labelledby="settings-planning">
			<h2 id="settings-planning">Planning</h2>
			<div className="settings-row">
				<span className="settings-label">
					Tracks
					<span className="settings-note">
						How many epics you can run at once across the board. {allocated} given to projects
						{tracks > allocated ? `, ${tracks - allocated} unallocated` : ", none unallocated"}. Each project's share is
						set on the Plan page.
					</span>
				</span>
				<span className="settings-step" role="group" aria-label="The board's tracks">
					<button
						type="button"
						className="quiet"
						disabled={busy || tracks <= Math.max(1, allocated)}
						aria-label="One track fewer for the board"
						title={
							tracks <= allocated
								? "Every track is given to a project - take one from a project first"
								: "One track fewer for the board"
						}
						onClick={() => changeTracks(tracks - 1)}
					>
						−
					</button>
					<output aria-live="polite">{tracks}</output>
					<button
						type="button"
						className="quiet"
						disabled={busy}
						aria-label="One track more for the board"
						title="One track more for the board, to give a project"
						onClick={() => changeTracks(tracks + 1)}
					>
						+
					</button>
				</span>
			</div>
			<div className="settings-label">
				Breaks
				<span className="settings-note">
					Days nobody works on the board or on one project, left out of the speed and the forecast.
				</span>
			</div>
			{breaks.length === 0 ? (
				<p className="settings-note">No breaks.</p>
			) : (
				<ul className="settings-list" aria-label="Breaks">
					{breaks.map((one) => (
						<li key={one.id}>
							<span>
								{one.name || "Break"} · {dayText(one.from)} to {dayText(one.to)} · {nameOf(one.project)}
							</span>
							<button
								type="button"
								className="quiet danger"
								disabled={busy}
								aria-label={`Remove the break ${one.name || one.id}`}
								onClick={() => removeBreak(one.id)}
							>
								Remove
							</button>
						</li>
					))}
				</ul>
			)}
			<form
				className="settings-form"
				aria-label="Add a break"
				onSubmit={(event) => {
					event.preventDefault();
					addBreak();
				}}
			>
				<input
					aria-label="Break name"
					placeholder="Leave, a holiday, a project put down…"
					value={draft.name}
					onChange={(event) => setDraft({ ...draft, name: event.target.value })}
				/>
				<input
					type="date"
					aria-label="First day of the break"
					required
					value={draft.from}
					onChange={(event) => setDraft({ ...draft, from: event.target.value, to: draft.to || event.target.value })}
				/>
				<input
					type="date"
					aria-label="Last day of the break"
					required
					min={draft.from || undefined}
					value={draft.to}
					onChange={(event) => setDraft({ ...draft, to: event.target.value })}
				/>
				<select
					aria-label="Whom the break is for"
					value={draft.project}
					onChange={(event) => setDraft({ ...draft, project: event.target.value })}
				>
					<option value="">Whole board</option>
					{projects.map((project) => (
						<option key={project.id} value={project.id}>
							{project.name}
						</option>
					))}
				</select>
				<button type="submit" disabled={busy || !draft.from || !draft.to || draft.to < draft.from}>
					Add break
				</button>
			</form>
			{error && (
				<p className="notice error" role="alert">
					{error}
				</p>
			)}
		</section>
	);
}

const NOTIFY_NOTE: Record<NotifyState, string> = {
	unsupported: "This browser cannot show notifications.",
	insecure: "Notifications need the board opened on localhost or over https.",
	denied: "Notifications are blocked for this site in the browser's settings.",
	off: "Show a desktop notification when something new arrives in the inbox while the board is open.",
	on: "A desktop notification shows when something new arrives in the inbox while the board is open.",
};

function Notifications() {
	const [notify, setNotifyState] = useState<NotifyState>("off");
	useEffect(() => {
		setNotifyState(notifyState());
		const update = () => setNotifyState(notifyState());
		window.addEventListener(NOTIFY_CHANGED, update);
		return () => window.removeEventListener(NOTIFY_CHANGED, update);
	}, []);
	return (
		<section className="settings-section" id="notifications" aria-labelledby="settings-notifications">
			<h2 id="settings-notifications">Notifications</h2>
			<div className="settings-row">
				<span className="settings-label">
					Desktop notifications
					<span className="settings-note">{NOTIFY_NOTE[notify]} Kept in this browser.</span>
				</span>
				<button
					type="button"
					className={`chip-toggle${notify === "on" ? " on" : ""}`}
					aria-pressed={notify === "on"}
					disabled={notify === "unsupported" || notify === "insecure" || notify === "denied"}
					onClick={async () => setNotifyState(await setNotify(notify !== "on"))}
				>
					{notify === "on" ? "On" : "Off"}
				</button>
			</div>
		</section>
	);
}

const BOARDS = {
	card: { label: "Cards", href: "/" },
	epic: { label: "Epics", href: "/epics" },
} as const;

function SavedViews({ views: initialViews }: { views: SavedView[] }) {
	const [views, setViews] = useState(initialViews);
	const [error, setError] = useState<string | null>(null);
	const [busy, startTransition] = useTransition();
	useEffect(() => setViews(initialViews), [initialViews]);

	function remove(view: SavedView) {
		setError(null);
		startTransition(async () => {
			const result = await forgetSavedView(view.kind, view.name);
			if (result.error || !result.views) {
				setError(`Could not delete the view ${view.name}: ${result.error ?? "board-card deleted nothing"}`);
				return;
			}
			setViews(result.views);
		});
	}

	const sorted = [...views].sort((a, b) => a.kind.localeCompare(b.kind) || a.name.localeCompare(b.name));
	return (
		<section className="settings-section" id="views" aria-labelledby="settings-views">
			<h2 id="settings-views">Saved views</h2>
			<span className="settings-note">Saved and brought back from the toolbar of the Cards and Epics boards.</span>
			{sorted.length === 0 ? (
				<p className="settings-note">No saved views.</p>
			) : (
				<ul className="settings-list" aria-label="Saved views">
					{sorted.map((view) => (
						<li key={`${view.kind}:${view.name}`}>
							<span>
								{view.name} ·{" "}
								<Link href={BOARDS[view.kind].href} className="settings-note">
									{BOARDS[view.kind].label}
								</Link>
							</span>
							<button
								type="button"
								className="quiet danger"
								disabled={busy}
								aria-label={`Delete the view ${view.name} of the ${BOARDS[view.kind].label} board`}
								onClick={() => remove(view)}
							>
								Delete
							</button>
						</li>
					))}
				</ul>
			)}
			{error && (
				<p className="notice error" role="alert">
					{error}
				</p>
			)}
		</section>
	);
}

export function Settings({
	tracks,
	breaks,
	projects,
	views,
}: {
	tracks: number;
	breaks: Break[];
	projects: Project[];
	views: SavedView[];
}) {
	return (
		<section className="settings">
			<h1>Settings</h1>
			<section className="settings-section" aria-labelledby="settings-appearance">
				<h2 id="settings-appearance">Appearance</h2>
				<div className="settings-row">
					<span className="settings-label">
						Theme
						<span className="settings-note">Kept in this browser. System follows the operating system.</span>
					</span>
					<ThemePicker />
				</div>
			</section>
			<Notifications />
			<Planning tracks={tracks} breaks={breaks} projects={projects} />
			<SavedViews views={views} />
		</section>
	);
}
