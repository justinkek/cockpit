"use client";

import { type ReactNode, useEffect, useMemo, useRef, useState } from "react";

export type Command = {
	id: string;
	label: string;
	hint?: string;
	group?: string;
	keywords?: string;
	icon?: ReactNode;
	run?: () => void;
	next?: () => Page;
};

export type Page = { title: string; items: Command[]; root?: boolean };

const SHOWN = 60;

function matching(items: Command[], query: string) {
	const words = query.toLowerCase().split(/\s+/).filter(Boolean);
	if (words.length === 0) return items;
	return items.filter((item) => {
		const text = `${item.label} ${item.hint ?? ""} ${item.keywords ?? ""}`.toLowerCase();
		return words.every((word) => text.includes(word));
	});
}

export function Palette({ start, onClose }: { start: Page; onClose: () => void }) {
	const [pages, setPages] = useState<Page[]>([start]);
	const [query, setQuery] = useState("");
	const [active, setActive] = useState(0);
	const box = useRef<HTMLInputElement>(null);
	const list = useRef<HTMLUListElement>(null);
	const page = pages.at(-1) ?? start;
	const found = useMemo(() => matching(page.items, query), [page, query]);
	const shown = found.slice(0, SHOWN);

	useEffect(() => {
		box.current?.focus();
	}, [pages.length]);

	useEffect(() => {
		list.current?.querySelector(`[data-index="${active}"]`)?.scrollIntoView({ block: "nearest" });
	}, [active]);

	function choose(item: Command | undefined) {
		if (!item) return;
		if (item.next) {
			setPages((current) => [...current, item.next?.() ?? start]);
			setQuery("");
			setActive(0);
			return;
		}
		onClose();
		item.run?.();
	}

	let group: string | undefined;
	return (
		<div
			className="overlay"
			role="presentation"
			onMouseDown={(event) => event.target === event.currentTarget && onClose()}
		>
			<div className="dialog palette" role="dialog" aria-modal="true" aria-label={page.title}>
				<div className="palette-head">
					{!page.root && <span className="palette-crumb">{page.title}</span>}
					<input
						ref={box}
						role="combobox"
						aria-expanded="true"
						aria-controls="palette-list"
						aria-activedescendant={shown[active] ? `palette-${active}` : undefined}
						placeholder={page.root ? "Type a command, or a card's id or name…" : "Filter…"}
						value={query}
						onChange={(event) => {
							setQuery(event.target.value);
							setActive(0);
						}}
						onKeyDown={(event) => {
							if (event.key === "ArrowDown" || (event.ctrlKey && event.key === "n")) {
								event.preventDefault();
								setActive((index) => Math.min(shown.length - 1, index + 1));
							} else if (event.key === "ArrowUp" || (event.ctrlKey && event.key === "p")) {
								event.preventDefault();
								setActive((index) => Math.max(0, index - 1));
							} else if (event.key === "Enter") {
								event.preventDefault();
								choose(shown[active]);
							} else if (event.key === "Escape") {
								event.preventDefault();
								event.stopPropagation();
								onClose();
							} else if (event.key === "Backspace" && query === "" && pages.length > 1) {
								event.preventDefault();
								setPages((current) => current.slice(0, -1));
								setActive(0);
							}
						}}
					/>
				</div>
				<ul className="palette-list" id="palette-list" role="listbox" ref={list}>
					{shown.length === 0 && <li className="palette-empty">Nothing matches</li>}
					{shown.map((item, index) => {
						const heading = item.group && item.group !== group ? item.group : null;
						group = item.group;
						return (
							<li key={item.id} role="presentation">
								{heading && <span className="palette-group">{heading}</span>}
								<button
									type="button"
									role="option"
									id={`palette-${index}`}
									data-index={index}
									aria-selected={index === active}
									className={index === active ? "on" : undefined}
									onMouseMove={() => setActive(index)}
									onClick={() => choose(item)}
								>
									{item.icon}
									<span className="palette-label">{item.label}</span>
									{item.hint && <span className="palette-hint">{item.hint}</span>}
									{item.next && <span className="palette-hint">›</span>}
								</button>
							</li>
						);
					})}
					{found.length > SHOWN && <li className="palette-empty">{found.length - SHOWN} more - keep typing</li>}
				</ul>
			</div>
		</div>
	);
}
