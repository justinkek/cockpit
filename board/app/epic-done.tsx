"use client";

import { useEffect, useRef } from "react";

export type Finishing = { id: string; name: string; open: { id: string; name: string }[]; rank?: number };

export function openTickets<T extends { id: string; name: string; status: string }>(cards: T[]) {
	return cards
		.filter((card) => card.status !== "Done" && card.status !== "Deprioritised")
		.map(({ id, name }) => ({ id, name }));
}

export function EpicDoneDialog({
	finishing,
	busy,
	onDeprioritise,
	onAnyway,
	onCancel,
}: {
	finishing: Finishing;
	busy: boolean;
	onDeprioritise: () => void;
	onAnyway: () => void;
	onCancel: () => void;
}) {
	const panel = useRef<HTMLDivElement>(null);
	useEffect(() => {
		panel.current?.focus();
	}, []);
	const count = finishing.open.length;
	const tickets = count === 1 ? "1 open ticket" : `${count} open tickets`;
	return (
		<div
			className="overlay"
			role="presentation"
			onMouseDown={(event) => event.target === event.currentTarget && onCancel()}
		>
			<div
				className="dialog epic-done"
				role="alertdialog"
				aria-modal="true"
				aria-label={`Move ${finishing.id} to Epic Done`}
				tabIndex={-1}
				ref={panel}
				onKeyDown={(event) => {
					if (event.key === "Escape") {
						event.preventDefault();
						event.stopPropagation();
						onCancel();
					}
				}}
			>
				<header className="dialog-head">
					<h2>
						{finishing.id} still has {tickets}
					</h2>
				</header>
				<p>
					{finishing.name} is moving to Epic Done while {count === 1 ? "this ticket is" : "these tickets are"} neither
					done nor deprioritised:
				</p>
				<ul>
					{finishing.open.map((card) => (
						<li key={card.id}>
							<span className="ident">{card.id}</span> {card.name}
						</li>
					))}
				</ul>
				<footer className="epic-done-actions">
					<button type="button" className="quiet" disabled={busy} onClick={onCancel}>
						Cancel
					</button>
					<span className="spacer" />
					<button type="button" className="quiet" disabled={busy} onClick={onAnyway}>
						Move it anyway
					</button>
					<button type="button" disabled={busy} onClick={onDeprioritise}>
						Deprioritise {count === 1 ? "it" : `all ${count}`} and move it
					</button>
				</footer>
			</div>
		</div>
	);
}
