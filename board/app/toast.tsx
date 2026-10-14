"use client";

import { useEffect, useRef } from "react";

export type Undoable = { key: number; id: string; since: string; text: string };

let made = 0;

export function undoable(id: string, since: string | undefined, text: string): Undoable | null {
	if (!since) return null;
	made += 1;
	return { key: made, id, since, text };
}

export function typingIn(target: EventTarget | null) {
	return (
		target instanceof HTMLElement && (/^(INPUT|SELECT|TEXTAREA)$/.test(target.tagName) || target.isContentEditable)
	);
}

export function UndoToast({
	toast,
	busy,
	onUndo,
	onDismiss,
}: {
	toast: Undoable | null;
	busy: boolean;
	onUndo: (toast: Undoable) => void;
	onDismiss: () => void;
}) {
	const latest = useRef({ toast, busy, onUndo, onDismiss });
	latest.current = { toast, busy, onUndo, onDismiss };

	useEffect(() => {
		if (!toast || busy) return;
		const timer = window.setTimeout(() => latest.current.onDismiss(), 10000);
		return () => window.clearTimeout(timer);
	}, [toast, busy]);

	useEffect(() => {
		function onKey(event: KeyboardEvent) {
			const { toast: shown, busy: undoing, onUndo: undo } = latest.current;
			if (!shown || undoing || typingIn(event.target)) return;
			if (event.key.toLowerCase() === "z" && (event.metaKey || event.ctrlKey) && !event.shiftKey) {
				event.preventDefault();
				undo(shown);
			}
		}
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	}, []);

	if (!toast) return null;
	return (
		<div className="toast" role="status">
			<span className="toast-text">{busy ? "Undoing…" : toast.text}</span>
			<button type="button" className="toast-undo" disabled={busy} onClick={() => onUndo(toast)} title="Undo (Cmd/Ctrl+Z)">
				Undo
			</button>
			<button type="button" className="quiet" aria-label="Dismiss" onClick={onDismiss}>
				×
			</button>
		</div>
	);
}
