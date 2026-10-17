"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";

export type SearchOption = { value: string; label: string; id?: string; done?: boolean };

const SHOWN = 60;

export function recordOptions(records: { id: string; name: string; status?: string }[], doneStatus: string): SearchOption[] {
	return records.map((record) => ({ value: record.id, id: record.id, label: record.name, done: record.status === doneStatus }));
}

export function optionsMatching(options: SearchOption[], query: string): SearchOption[] {
	const words = query.trim().toLowerCase().split(/\s+/).filter(Boolean);
	if (words.length === 0) return options.filter((option) => !option.done);
	const scored = options.flatMap((option) => {
		const id = (option.id ?? "").toLowerCase();
		const text = `${id} ${option.label.toLowerCase()}`;
		if (!words.every((word) => text.includes(word))) return [];
		const first = words[0];
		const rank = id && (id === first || id.split("-").at(-1) === first) ? 0 : id.startsWith(first) ? 1 : 2;
		return [{ option, rank }];
	});
	return scored.sort((a, b) => a.rank - b.rank).map(({ option }) => option);
}

export function SearchSelect({
	label,
	name,
	value,
	options,
	onChange,
}: {
	label: string;
	name?: string;
	value: string;
	options: SearchOption[];
	onChange: (value: string) => void;
}) {
	const [open, setOpen] = useState(false);
	const [query, setQuery] = useState("");
	const [active, setActive] = useState(0);
	const frame = useRef<HTMLDivElement>(null);
	const button = useRef<HTMLButtonElement>(null);
	const search = useRef<HTMLInputElement>(null);
	const list = useRef<HTMLUListElement>(null);
	const listId = useId();

	const found = useMemo(() => optionsMatching(options, query), [options, query]);
	const shown = found.slice(0, SHOWN);
	const current = options.find((option) => option.value === value);

	useEffect(() => {
		if (!open) return;
		setQuery("");
		setActive(Math.max(optionsMatching(options, "").findIndex((option) => option.value === value), 0));
		search.current?.focus();
		function onDown(event: PointerEvent) {
			if (frame.current && !frame.current.contains(event.target as Node)) setOpen(false);
		}
		document.addEventListener("pointerdown", onDown);
		return () => document.removeEventListener("pointerdown", onDown);
	}, [open]);

	useEffect(() => {
		if (open) list.current?.querySelector(`[data-index="${active}"]`)?.scrollIntoView({ block: "nearest" });
	}, [active, open]);

	function close() {
		setOpen(false);
		button.current?.focus();
	}

	function pick(option: SearchOption | undefined) {
		if (!option) return;
		close();
		if (option.value !== value) onChange(option.value);
	}

	return (
		<div className="search-select" ref={frame}>
			{name && <input type="hidden" name={name} value={value} />}
			<button
				ref={button}
				type="button"
				className="search-select-open"
				aria-label={`${label}: ${current?.label ?? value}`}
				aria-expanded={open}
				aria-haspopup="listbox"
				onClick={() => setOpen(!open)}
				onKeyDown={(event) => {
					if (event.key === "ArrowDown" || event.key === "ArrowUp") {
						event.preventDefault();
						setOpen(true);
					}
				}}
			>
				<span className="search-select-label">{current?.label ?? value}</span>
				<span className="search-select-caret" aria-hidden="true">
					▾
				</span>
			</button>
			{open && (
				<div className="card-picker-panel search-select-panel" role="dialog" aria-label={label}>
					<input
						ref={search}
						type="search"
						role="combobox"
						aria-expanded="true"
						aria-controls={listId}
						aria-activedescendant={shown[active] ? `${listId}-${active}` : undefined}
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
								close();
							} else if (event.key === "Tab") {
								setOpen(false);
							}
						}}
					/>
					<ul id={listId} ref={list} role="listbox" aria-label={label}>
						{shown.map((option, index) => (
							<li
								key={option.value}
								id={`${listId}-${index}`}
								role="option"
								aria-selected={option.value === value}
								data-index={index}
								className={[index === active && "active", option.value === value && "chosen", option.done && "done"]
									.filter(Boolean)
									.join(" ")}
								onPointerMove={() => setActive(index)}
								onPointerDown={(event) => event.preventDefault()}
								onClick={() => pick(option)}
							>
								{option.id && <span className="ident">{option.id}</span>}
								<span className="card-picker-name">{option.label}</span>
								{option.done && <span className="search-select-done">Done</span>}
							</li>
						))}
						{found.length === 0 && <li className="empty">Nothing matches</li>}
						{found.length > SHOWN && (
							<li className="empty">{found.length - SHOWN} more - type more of the id or name</li>
						)}
					</ul>
				</div>
			)}
		</div>
	);
}
