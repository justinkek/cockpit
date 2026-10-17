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

export function EpicsDoneDialog({
	finishing,
	total,
	onDeprioritise,
	onAnyway,
	onCancel,
}: {
	finishing: Finishing[];
	total: number;
	onDeprioritise: () => void;
	onAnyway: () => void;
	onCancel: () => void;
}) {
	const panel = useRef<HTMLDivElement>(null);
	useEffect(() => {
		panel.current?.focus();
	}, []);
	const count = finishing.reduce((sum, epic) => sum + epic.open.length, 0);
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
				aria-label={`Move ${total} epics to Epic Done`}
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
						{finishing.length} of {total} epics still {finishing.length === 1 ? "has" : "have"} {tickets}
					</h2>
				</header>
				<p>
					{total} epics are moving to Epic Done while {finishing.length === 1 ? "this one has" : "these have"} tickets
					neither done nor deprioritised:
				</p>
				<ul>
					{finishing.map((epic) => (
						<li key={epic.id}>
							<span className="ident">{epic.id}</span> {epic.name}{" "}
							<span className="count">
								{epic.open.length === 1 ? "1 open ticket" : `${epic.open.length} open tickets`}
							</span>
						</li>
					))}
				</ul>
				<footer className="epic-done-actions">
					<button type="button" className="quiet" onClick={onCancel}>
						Cancel
					</button>
					<span className="spacer" />
					<button type="button" className="quiet" onClick={onAnyway}>
						Move them anyway
					</button>
					<button type="button" onClick={onDeprioritise}>
						Deprioritise {count === 1 ? "it" : `all ${count}`} and move them
					</button>
				</footer>
			</div>
		</div>
	);
}

export type Closing = { id: string; name: string; epics: number; tickets: number };

export function ProjectDoneDialog({
	closing,
	busy,
	onClose,
	onAnyway,
	onCancel,
}: {
	closing: Closing;
	busy: boolean;
	onClose: () => void;
	onAnyway: () => void;
	onCancel: () => void;
}) {
	const panel = useRef<HTMLDivElement>(null);
	useEffect(() => {
		panel.current?.focus();
	}, []);
	const open = [
		closing.epics === 0 ? "" : closing.epics === 1 ? "1 open epic" : `${closing.epics} open epics`,
		closing.tickets === 0 ? "" : closing.tickets === 1 ? "1 open ticket" : `${closing.tickets} open tickets`,
	]
		.filter(Boolean)
		.join(" and ");
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
				aria-label={`Mark ${closing.id} Done`}
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
						{closing.id} still has {open}
					</h2>
				</header>
				<p>
					{closing.name} is being marked Done while work in it is still open. Closing it deprioritises every ticket that
					is neither done nor deprioritised and moves every epic not in Epic Done there, in one change. Marking it Done
					anyway leaves that work where it is.
				</p>
				<footer className="epic-done-actions">
					<button type="button" className="quiet" disabled={busy} onClick={onCancel}>
						Cancel
					</button>
					<span className="spacer" />
					<button type="button" className="quiet" disabled={busy} onClick={onAnyway}>
						Mark Done anyway
					</button>
					<button type="button" disabled={busy} onClick={onClose}>
						Deprioritise and close everything
					</button>
				</footer>
			</div>
		</div>
	);
}
