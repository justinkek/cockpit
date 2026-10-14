"use client";

import { useEffect, useRef } from "react";

export async function copyText(text: string): Promise<boolean> {
	try {
		if (navigator.clipboard && window.isSecureContext) {
			await navigator.clipboard.writeText(text);
			return true;
		}
	} catch {}
	const area = document.createElement("textarea");
	area.value = text;
	area.setAttribute("readonly", "");
	area.style.position = "fixed";
	area.style.opacity = "0";
	document.body.append(area);
	area.select();
	let copied = false;
	try {
		copied = document.execCommand("copy");
	} catch {}
	area.remove();
	return copied;
}

export function cardLink(id: string) {
	return `${window.location.origin}/card/${encodeURIComponent(id)}`;
}

export function useKeys(handler: (event: KeyboardEvent) => void) {
	const latest = useRef(handler);
	latest.current = handler;
	useEffect(() => {
		const listener = (event: KeyboardEvent) => latest.current(event);
		window.addEventListener("keydown", listener);
		return () => window.removeEventListener("keydown", listener);
	}, []);
}

export type Shortcut = { keys: string[]; label: string };

export function ShortcutHelp({ shortcuts, onClose }: { shortcuts: Shortcut[]; onClose: () => void }) {
	const panel = useRef<HTMLDivElement>(null);
	useEffect(() => {
		panel.current?.focus();
	}, []);
	return (
		<div className="overlay" role="presentation" onMouseDown={(event) => event.target === event.currentTarget && onClose()}>
			<div
				className="dialog shortcuts"
				role="dialog"
				aria-modal="true"
				aria-label="Keyboard shortcuts"
				tabIndex={-1}
				ref={panel}
				onKeyDown={(event) => {
					if (event.key === "Escape" || event.key === "?") {
						event.preventDefault();
						event.stopPropagation();
						onClose();
					}
				}}
			>
				<header className="dialog-head">
					<h2>Keyboard shortcuts</h2>
					<button type="button" className="quiet" onClick={onClose}>
						Close
					</button>
				</header>
				<dl>
					{shortcuts.map((shortcut) => (
						<div key={shortcut.label}>
							<dt>{shortcut.label}</dt>
							<dd>
								{shortcut.keys.map((key) => (
									<kbd key={key}>{key}</kbd>
								))}
							</dd>
						</div>
					))}
				</dl>
			</div>
		</div>
	);
}
