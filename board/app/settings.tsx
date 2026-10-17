"use client";

import { ThemePicker } from "@/app/theme";

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
		</section>
	);
}
