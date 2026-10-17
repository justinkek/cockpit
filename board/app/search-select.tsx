"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
import { type Choice, chosen, cycled, markOf, NO_CHOICE } from "@/app/view";

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

export function choiceSummary(choice: Choice, options: SearchOption[], all: string) {
	const name = (value: string) => options.find((option) => option.value === value)?.label ?? value;
	const { include, exclude } = choice;
	if (include.length === 0 && exclude.length === 0) return all;
	if (include.length === 1 && exclude.length === 0) return name(include[0]);
	if (include.length === 0 && exclude.length === 1) return `Not ${name(exclude[0])}`;
	const parts = [include.length > 0 && `${include.length} included`, exclude.length > 0 && `${exclude.length} excluded`];
	return parts.filter(Boolean).join(", ");
}

const MARKS = { include: "+", exclude: "−" } as const;

export function ChoiceSelect({
	label,
	all,
	value,
	options,
	onChange,
}: {
	label: string;
	all: string;
	value: Choice;
	options: SearchOption[];
	onChange: (value: Choice) => void;
}) {
	const [open, setOpen] = useState(false);
	const [query, setQuery] = useState("");
	const [active, setActive] = useState(0);
	const [moved, setMoved] = useState(false);
	const frame = useRef<HTMLDivElement>(null);
	const button = useRef<HTMLButtonElement>(null);
	const search = useRef<HTMLInputElement>(null);
	const list = useRef<HTMLUListElement>(null);
	const listId = useId();

	const found = useMemo(
		() => (query.trim() ? optionsMatching(options, query) : options.filter((option) => !option.done || markOf(value, option.value))),
		[options, query, value],
	);
	const shown = found.slice(0, SHOWN);
	const summary = choiceSummary(value, options, all);
	const count = chosen(value);
	const shownSummary = count > 1 ? `${label}: ${summary}` : summary;

	useEffect(() => {
		if (!open) return;
		setQuery("");
		setActive(0);
		setMoved(false);
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

	function cycle(option: SearchOption | undefined) {
		if (option) onChange(cycled(value, option.value));
	}

	return (
		<div className="search-select" ref={frame}>
			<button
				ref={button}
				type="button"
				className={`search-select-open${count > 0 ? " on" : ""}`}
				aria-label={`${label}: ${summary}`}
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
				<span className="search-select-label" title={shownSummary}>
					{shownSummary}
				</span>
				<span className="search-select-caret" aria-hidden="true">
					▾
				</span>
			</button>
			{open && (
				<div className="card-picker-panel search-select-panel" role="dialog" aria-label={label}>
					<div className="choice-head">
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
								setMoved(false);
							}}
							onKeyDown={(event) => {
								if (event.key === "ArrowDown" || event.key === "ArrowUp") {
									event.preventDefault();
									const step = event.key === "ArrowDown" ? 1 : -1;
									setActive((at) => Math.min(Math.max(at + step, 0), Math.max(shown.length - 1, 0)));
									setMoved(true);
								} else if (event.key === "Enter" || (event.key === " " && (moved || !query))) {
									event.preventDefault();
									event.stopPropagation();
									cycle(shown[active]);
								} else if (event.key === "Escape") {
									event.preventDefault();
									event.stopPropagation();
									close();
								} else if (event.key === "Tab") {
									setOpen(false);
								}
							}}
						/>
						<button
							type="button"
							className="choice-clear"
							disabled={count === 0}
							onPointerDown={(event) => event.preventDefault()}
							onClick={() => {
								onChange(NO_CHOICE);
								search.current?.focus();
							}}
						>
							Clear
						</button>
					</div>
					<p className="choice-hint">Click a row to include it, again to exclude it and again to clear it.</p>
					<ul id={listId} ref={list} role="listbox" aria-label={label} aria-multiselectable="true">
						{shown.map((option, index) => {
							const mark = markOf(value, option.value);
							return (
								<li
									key={option.value}
									id={`${listId}-${index}`}
									role="option"
									aria-selected={mark !== null}
									aria-label={`${option.id ? `${option.id} ` : ""}${option.label}${mark ? `, ${mark}d` : ""}`}
									data-index={index}
									data-mark={mark ?? undefined}
									className={[index === active && "active", mark && "chosen", option.done && "done"].filter(Boolean).join(" ")}
									onPointerMove={() => setActive(index)}
									onPointerDown={(event) => event.preventDefault()}
									onClick={() => {
										setActive(index);
										cycle(option);
									}}
								>
									<span className={`choice-mark${mark ? ` ${mark}` : ""}`} aria-hidden="true">
										{mark ? MARKS[mark] : ""}
									</span>
									{option.id && <span className="ident">{option.id}</span>}
									<span className="card-picker-name">{option.label}</span>
									{option.done && <span className="search-select-done">Done</span>}
								</li>
							);
						})}
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
