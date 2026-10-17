"use client";

import Link from "next/link";
import { useEffect, useState, useTransition } from "react";
import { forgetSavedView } from "@/app/actions";
import { NOTIFY_CHANGED, type NotifyState, notifyState, setNotify } from "@/app/notify";
import { ThemePicker } from "@/app/theme";
import type { SavedView } from "@/lib/shared";

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

export function Settings({ views }: { views: SavedView[] }) {
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
			<SavedViews views={views} />
		</section>
	);
}
