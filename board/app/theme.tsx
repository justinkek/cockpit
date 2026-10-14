"use client";

import { useEffect, useState } from "react";
import { THEME_KEY as KEY } from "@/lib/theme";

export type Theme = "system" | "light" | "dark";

const CHANGED = "cockpit-theme-change";

function savedTheme(): Theme {
	try {
		const saved = window.localStorage.getItem(KEY);
		return saved === "light" || saved === "dark" ? saved : "system";
	} catch {
		return "system";
	}
}

function showTheme(theme: Theme) {
	const root = document.documentElement;
	if (theme === "system") delete root.dataset.theme;
	else root.dataset.theme = theme;
	window.dispatchEvent(new Event(CHANGED));
}

export function applyTheme(theme: Theme) {
	try {
		if (theme === "system") window.localStorage.removeItem(KEY);
		else window.localStorage.setItem(KEY, theme);
	} catch {}
	showTheme(theme);
}

export function darkNow() {
	const chosen = document.documentElement.dataset.theme;
	if (chosen === "dark") return true;
	if (chosen === "light") return false;
	return window.matchMedia("(prefers-color-scheme: dark)").matches;
}

export function onThemeChange(listener: () => void) {
	const scheme = window.matchMedia("(prefers-color-scheme: dark)");
	scheme.addEventListener("change", listener);
	window.addEventListener(CHANGED, listener);
	return () => {
		scheme.removeEventListener("change", listener);
		window.removeEventListener(CHANGED, listener);
	};
}

export function ThemeSwitch() {
	const [theme, setTheme] = useState<Theme>("system");
	useEffect(() => {
		setTheme(savedTheme());
		function fromAnotherTab(event: StorageEvent) {
			if (event.key === KEY || event.key === null) showTheme(savedTheme());
		}
		window.addEventListener("storage", fromAnotherTab);
		const stop = onThemeChange(() => setTheme(savedTheme()));
		return () => {
			window.removeEventListener("storage", fromAnotherTab);
			stop();
		};
	}, []);
	return (
		<select
			className="theme-switch"
			aria-label="Theme"
			value={theme}
			onChange={(event) => applyTheme(event.target.value as Theme)}
		>
			<option value="system">System theme</option>
			<option value="light">Light</option>
			<option value="dark">Dark</option>
		</select>
	);
}
