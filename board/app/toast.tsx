"use client";

import { useEffect, useRef } from "react";

export type Change = { id: string; since: string; until: string };

export type Undoable = { key: number; text: string; changes: Change[] };

let made = 0;

export function undoable(
	id: string,
	span: { since: string; until: string } | undefined,
	text: string,
): Undoable | null {
	if (!span) return null;
	made += 1;
	return { key: made, text, changes: [{ id, ...span }] };
}

export function toastOf(text: string, changes: Change[] = []): Undoable {
	made += 1;
	return { key: made, text, changes };
}

export function typingIn(target: EventTarget | null) {
	return (
		target instanceof HTMLElement && (/^(INPUT|SELECT|TEXTAREA)$/.test(target.tagName) || target.isContentEditable)
	);
}

const TEXT_INPUTS = /^(text|search|email|url|tel|password|number|date|datetime-local|month|week|time)$/;

function editingText(target: EventTarget | null) {
	if (!(target instanceof HTMLElement)) return false;
	if (target.isContentEditable || target.tagName === "TEXTAREA") return true;
	return target instanceof HTMLInputElement && TEXT_INPUTS.test(target.type);
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
			if (!shown || shown.changes.length === 0 || undoing || editingText(event.target)) return;
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
			{toast.changes.length > 0 && (
				<button type="button" className="toast-undo" disabled={busy} onClick={() => onUndo(toast)} title="Undo (Cmd/Ctrl+Z)">
					Undo
				</button>
			)}
			<button type="button" className="quiet" aria-label="Dismiss" onClick={onDismiss}>
				×
			</button>
		</div>
	);
}
