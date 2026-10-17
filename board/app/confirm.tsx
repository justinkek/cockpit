"use client";

import { type ReactNode, useCallback, useEffect, useRef, useState } from "react";

type Asking = { title: string; detail?: string; yes: string; answer: (yes: boolean) => void };

export type Ask = (title: string, options?: { detail?: string; yes?: string }) => Promise<boolean>;

function ConfirmDialog({ asking, onAnswer }: { asking: Asking; onAnswer: (yes: boolean) => void }) {
	const confirm = useRef<HTMLButtonElement>(null);
	useEffect(() => {
		confirm.current?.focus();
	}, []);
	return (
		<div
			className="overlay"
			role="presentation"
			onMouseDown={(event) => event.target === event.currentTarget && onAnswer(false)}
		>
			<div
				className="dialog epic-done"
				role="alertdialog"
				aria-modal="true"
				aria-label={asking.title}
				tabIndex={-1}
				onKeyDown={(event) => {
					if (event.key === "Escape") {
						event.preventDefault();
						event.stopPropagation();
						onAnswer(false);
					}
				}}
			>
				<header className="dialog-head">
					<h2>{asking.title}</h2>
				</header>
				{asking.detail && <p>{asking.detail}</p>}
				<footer className="epic-done-actions">
					<button type="button" className="quiet" onClick={() => onAnswer(false)}>
						Cancel
					</button>
					<span className="spacer" />
					<button type="button" ref={confirm} onClick={() => onAnswer(true)}>
						{asking.yes}
					</button>
				</footer>
			</div>
		</div>
	);
}

export function useConfirm(): [ReactNode, Ask] {
	const [asking, setAsking] = useState<Asking | null>(null);
	const ask = useCallback<Ask>(
		(title, options = {}) =>
			new Promise<boolean>((resolve) =>
				setAsking({ title, detail: options.detail, yes: options.yes ?? "Yes", answer: resolve }),
			),
		[],
	);
	const dialog = asking ? (
		<ConfirmDialog
			asking={asking}
			onAnswer={(yes) => {
				setAsking(null);
				asking.answer(yes);
			}}
		/>
	) : null;
	return [dialog, ask];
}

export function finishedEpic(epics: { id: string; status?: string }[], id: string | null | undefined) {
	return id ? epics.find((epic) => epic.id === id && epic.status === "Epic Done")?.id : undefined;
}

export function askMoveDone(ask: Ask, count = 1) {
	return ask(
		count === 1 ? "This ticket is Done - move it anyway?" : `${count} of these tickets are Done - move them anyway?`,
		{ yes: count === 1 ? "Move it anyway" : "Move them anyway" },
	);
}

export function askFinishedEpic(ask: Ask, epic: string) {
	return ask(`${epic} is finished - add it anyway?`, {
		detail: `${epic} is in Epic Done. A ticket under it is planned and counted as part of an epic that is already delivered.`,
		yes: "Add it anyway",
	});
}

export function askOverShares(ask: Ask, shares: number, tracks: number) {
	return ask(`Shares would add up to ${shares} of ${tracks} tracks - set anyway?`, {
		detail:
			"The plan schedules every share it is given, so the projects together run more epics at once than the board has tracks for.",
		yes: "Set anyway",
	});
}
