"use client";

import { useEffect, useId, useRef, useState } from "react";
import { useHydrated } from "@/app/fields";
import { EMOJI_GROUPS, findEmoji } from "@/lib/emoji";

export function EmojiPicker({
	value,
	onPick,
	label = "Icon",
	name,
}: {
	value: string;
	onPick: (emoji: string) => void;
	label?: string;
	name?: string;
}) {
	const hydrated = useHydrated();
	const [open, setOpen] = useState(false);
	const [query, setQuery] = useState("");
	const [typed, setTyped] = useState("");
	const frame = useRef<HTMLDivElement>(null);
	const search = useRef<HTMLInputElement>(null);
	const panel = useId();

	useEffect(() => {
		if (!open) return;
		setQuery("");
		setTyped("");
		search.current?.focus();
		function onDown(event: PointerEvent) {
			if (frame.current && !frame.current.contains(event.target as Node)) setOpen(false);
		}
		document.addEventListener("pointerdown", onDown);
		return () => document.removeEventListener("pointerdown", onDown);
	}, [open]);

	if (!hydrated) {
		return <input name={name ?? "value"} aria-label={label} placeholder="No icon - one emoji" defaultValue={value} />;
	}

	function pick(emoji: string) {
		setOpen(false);
		if (emoji !== value) onPick(emoji);
	}

	const found = query.trim() ? findEmoji(query) : null;
	const groups = found ? [{ name: `${found.length} found`, emoji: found }] : EMOJI_GROUPS;

	return (
		<div className="emoji-picker" ref={frame}>
			{name && <input type="hidden" name={name} value={value} />}
			<button
				type="button"
				className={`emoji-current${value ? "" : " empty"}`}
				aria-label={value ? `${label}: ${value} - change it` : `${label}: none - pick one`}
				aria-expanded={open}
				aria-controls={panel}
				onClick={() => setOpen(!open)}
			>
				{value || "☺"}
				<span className="emoji-current-label">{value ? "Change" : "Add icon"}</span>
			</button>
			{open && (
				<div
					id={panel}
					className="emoji-panel"
					role="dialog"
					aria-label={`Pick the ${label.toLowerCase()}`}
					onKeyDown={(event) => {
						if (event.key === "Escape") {
							event.preventDefault();
							event.stopPropagation();
							setOpen(false);
						}
					}}
				>
					<div className="emoji-tools">
						<input
							ref={search}
							type="search"
							aria-label="Search emoji"
							placeholder="Search - rocket, bug, chart…"
							value={query}
							onChange={(event) => setQuery(event.target.value)}
							onKeyDown={(event) => {
								if (event.key === "Enter") {
									event.preventDefault();
									event.stopPropagation();
									if (found?.[0]) pick(found[0].emoji);
								}
							}}
						/>
						{value && (
							<button type="button" className="quiet" onClick={() => pick("")}>
								Remove
							</button>
						)}
					</div>
					<div className="emoji-grid-scroll">
						{groups.map((group) => (
							<section key={group.name}>
								<h4>{group.name}</h4>
								<div className="emoji-grid">
									{group.emoji.map((entry) => (
										<button
											type="button"
											key={entry.emoji}
											className={entry.emoji === value ? "on" : undefined}
											title={entry.words}
											aria-label={entry.words.split(" ")[0]}
											onClick={() => pick(entry.emoji)}
										>
											{entry.emoji}
										</button>
									))}
								</div>
							</section>
						))}
						{found?.length === 0 && <p className="empty">No emoji matches - paste any emoji below.</p>}
					</div>
					<div className="emoji-own">
						<input
							aria-label="Any other emoji"
							placeholder="Or paste any emoji"
							value={typed}
							onChange={(event) => setTyped(event.target.value)}
							onKeyDown={(event) => {
								if (event.key === "Enter") {
									event.preventDefault();
									if (typed.trim()) pick(typed.trim());
								}
							}}
						/>
						<button type="button" disabled={!typed.trim()} onClick={() => pick(typed.trim())}>
							Use
						</button>
					</div>
				</div>
			)}
		</div>
	);
}
