"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
import { phaseOf } from "@/lib/shared";

export type Pickable = { id: string; name: string; status: string };

const SHOWN = 60;

export function cardsMatching(cards: Pickable[], query: string): Pickable[] {
	const words = query.trim().toLowerCase().split(/\s+/).filter(Boolean);
	if (words.length === 0) return cards;
	const scored = cards.flatMap((card) => {
		const id = card.id.toLowerCase();
		const text = `${id} ${card.name.toLowerCase()}`;
		if (!words.every((word) => text.includes(word))) return [];
		const first = words[0];
		const rank = id === first || id.split("-").at(-1) === first ? 0 : id.startsWith(first) ? 1 : 2;
		return [{ card, rank }];
	});
	return scored.sort((a, b) => a.rank - b.rank).map(({ card }) => card);
}

export function CardPicker({
	label,
	cards,
	onPick,
}: {
	label: string;
	cards: Pickable[];
	onPick: (id: string) => void;
}) {
	const [open, setOpen] = useState(false);
	const [query, setQuery] = useState("");
	const [active, setActive] = useState(0);
	const frame = useRef<HTMLDivElement>(null);
	const search = useRef<HTMLInputElement>(null);
	const list = useRef<HTMLUListElement>(null);
	const listId = useId();

	const found = useMemo(() => cardsMatching(cards, query), [cards, query]);
	const shown = found.slice(0, SHOWN);

	useEffect(() => {
		if (!open) return;
		setQuery("");
		setActive(0);
		search.current?.focus();
		function onDown(event: PointerEvent) {
			if (frame.current && !frame.current.contains(event.target as Node)) setOpen(false);
		}
		document.addEventListener("pointerdown", onDown);
		return () => document.removeEventListener("pointerdown", onDown);
	}, [open]);

	useEffect(() => {
		list.current?.querySelector(`[data-index="${active}"]`)?.scrollIntoView({ block: "nearest" });
	}, [active]);

	function pick(card: Pickable | undefined) {
		if (!card) return;
		setOpen(false);
		onPick(card.id);
	}

	return (
		<div className="card-picker" ref={frame}>
			<button
				type="button"
				className="card-picker-open"
				aria-expanded={open}
				aria-haspopup="listbox"
				disabled={cards.length === 0}
				onClick={() => setOpen(!open)}
			>
				<span aria-hidden="true">+</span> {label}
			</button>
			{open && (
				<div className="card-picker-panel" role="dialog" aria-label={label}>
					<input
						ref={search}
						type="search"
						role="combobox"
						aria-expanded="true"
						aria-controls={listId}
						aria-activedescendant={shown[active] ? `${listId}-${shown[active].id}` : undefined}
						aria-label={`${label}: search by id or name`}
						placeholder="Search by id or name…"
						value={query}
						onChange={(event) => {
							setQuery(event.target.value);
							setActive(0);
						}}
						onKeyDown={(event) => {
							if (event.key === "ArrowDown" || event.key === "ArrowUp") {
								event.preventDefault();
								const step = event.key === "ArrowDown" ? 1 : -1;
								setActive((at) => Math.min(Math.max(at + step, 0), Math.max(shown.length - 1, 0)));
							} else if (event.key === "Enter") {
								event.preventDefault();
								event.stopPropagation();
								pick(shown[active]);
							} else if (event.key === "Escape") {
								event.preventDefault();
								event.stopPropagation();
								setOpen(false);
							}
						}}
					/>
					<ul id={listId} ref={list} role="listbox" aria-label="Cards">
						{shown.map((card, index) => (
							<li
								key={card.id}
								id={`${listId}-${card.id}`}
								role="option"
								aria-selected={index === active}
								data-index={index}
								className={index === active ? "active" : undefined}
								onPointerMove={() => setActive(index)}
								onPointerDown={(event) => event.preventDefault()}
								onClick={() => pick(card)}
							>
								<span className={`dot phase-${phaseOf(card.status)}`} title={card.status} aria-hidden="true" />
								<span className="ident">{card.id}</span>
								<span className="card-picker-name">{card.name}</span>
							</li>
						))}
						{found.length === 0 && <li className="empty">No card matches</li>}
						{found.length > SHOWN && (
							<li className="empty">{found.length - SHOWN} more - type more of the id or name</li>
						)}
					</ul>
				</div>
			)}
		</div>
	);
}
