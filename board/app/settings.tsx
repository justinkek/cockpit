"use client";

import { useEffect, useState } from "react";
import { NOTIFY_CHANGED, type NotifyState, notifyState, setNotify } from "@/app/notify";
import { ThemePicker } from "@/app/theme";

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

export function Settings() {
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
		</section>
	);
}
