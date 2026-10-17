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

export function ThemeSync() {
	useEffect(() => {
		function fromAnotherTab(event: StorageEvent) {
			if (event.key === KEY || event.key === null) showTheme(savedTheme());
		}
		window.addEventListener("storage", fromAnotherTab);
		return () => window.removeEventListener("storage", fromAnotherTab);
	}, []);
	return null;
}

const THEMES: { value: Theme; label: string }[] = [
	{ value: "system", label: "System" },
	{ value: "light", label: "Light" },
	{ value: "dark", label: "Dark" },
];

export function ThemePicker() {
	const [theme, setTheme] = useState<Theme>("system");
	useEffect(() => {
		setTheme(savedTheme());
		return onThemeChange(() => setTheme(savedTheme()));
	}, []);
	return (
		<span className="segmented" role="group" aria-label="Theme">
			{THEMES.map((option) => (
				<button
					key={option.value}
					type="button"
					className={theme === option.value ? "on" : undefined}
					aria-pressed={theme === option.value}
					onClick={() => applyTheme(option.value)}
				>
					{option.label}
				</button>
			))}
		</span>
	);
}
