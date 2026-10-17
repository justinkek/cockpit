"use client";

import { useEffect, useRef, useState } from "react";
import type { Break } from "@/lib/shared";

export type Change = { id: string; since: string; until: string };

export type BreakUndo = { remove: string } | { restore: Break };

export type Undoable = { key: number; text: string; changes: Change[]; breakUndo?: BreakUndo };

export function canUndo(toast: Undoable) {
	return toast.changes.length > 0 || toast.breakUndo != null;
}

let made = 0;

export function undoable(
	id: string,
	span: { since: string; until: string } | undefined,
	text: string,
	more: Change[] = [],
): Undoable | null {
	if (!span) return null;
	made += 1;
	const held =
		more.length === 0 ? "" : ` and the due date of ${more.length === 1 ? more[0].id : `${more.length} tickets`}`;
	return { key: made, text: `${text}${held}`, changes: [{ id, ...span }, ...more] };
}

export function withNewId(text: string, from: string, to: string) {
	return from === to ? text : `${text}, so it is now ${to}`;
}

let carried: { id: string; toast: Undoable } | null = null;

export function carryTo(id: string, toast: Undoable | null) {
	carried = toast ? { id, toast } : null;
}

export function takeCarried(id: string): Undoable | null {
	if (carried?.id !== id) return null;
	const { toast } = carried;
	carried = null;
	return toast;
}

export function toastOf(text: string, changes: Change[] = []): Undoable {
	made += 1;
	return { key: made, text, changes };
}

export function breakToastOf(text: string, breakUndo: BreakUndo): Undoable {
	made += 1;
	return { key: made, text, changes: [], breakUndo };
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

	const [held, setHeld] = useState(false);

	useEffect(() => {
		if (!toast || busy || held) return;
		const timer = window.setTimeout(() => latest.current.onDismiss(), canUndo(toast) ? 20000 : 8000);
		return () => window.clearTimeout(timer);
	}, [toast, busy, held]);

	useEffect(() => {
		if (!toast) setHeld(false);
	}, [toast]);

	useEffect(() => {
		function onKey(event: KeyboardEvent) {
			const { toast: shown, busy: undoing, onUndo: undo } = latest.current;
			if (!shown || !canUndo(shown) || undoing || editingText(event.target)) return;
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
		<div
			className="toast"
			role="status"
			onPointerEnter={() => setHeld(true)}
			onPointerLeave={() => setHeld(false)}
			onFocus={() => setHeld(true)}
			onBlur={(event) => {
				if (!event.currentTarget.contains(event.relatedTarget)) setHeld(false);
			}}
		>
			<span className="toast-text">{busy ? "Undoing…" : toast.text}</span>
			{canUndo(toast) && (
				<button
					type="button"
					className="toast-undo"
					disabled={busy}
					onClick={() => onUndo(toast)}
					title="Undo (Cmd/Ctrl+Z)"
				>
					Undo
				</button>
			)}
			<button type="button" className="quiet" aria-label="Dismiss" onClick={onDismiss}>
				×
			</button>
		</div>
	);
}
