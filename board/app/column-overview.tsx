"use client";

import { type RefObject, useCallback, useEffect, useState } from "react";
import { phaseOf, type Stub } from "@/lib/shared";

type Bar = { column: string; count: number; blocked: number; folded: boolean };

function lanesOf(root: HTMLElement, column: string) {
	return [...root.querySelectorAll<HTMLElement>("[data-column]")].filter((lane) => lane.dataset.column === column);
}

function scrollerOf(lane: HTMLElement) {
	let node = lane.parentElement;
	while (node) {
		const overflow = getComputedStyle(node).overflowX;
		if ((overflow === "auto" || overflow === "scroll") && node.scrollWidth > node.clientWidth) return node;
		node = node.parentElement;
	}
	return null;
}

export function ColumnOverview({
	columns,
	visible,
	folded,
	workspace,
}: {
	columns: string[];
	visible: Stub[];
	folded: string[];
	workspace: RefObject<HTMLDivElement | null>;
}) {
	const [inView, setInView] = useState<Set<string>>(new Set());
	const bars: Bar[] = columns.map((column) => {
		const here = visible.filter((stub) => stub.status === column);
		return {
			column,
			count: here.length,
			blocked: here.filter((stub) => stub.blocked).length,
			folded: folded.includes(column),
		};
	});
	const most = Math.max(1, ...bars.map((bar) => bar.count));

	const measure = useCallback(() => {
		const root = workspace.current;
		if (!root) return;
		const seen = new Set<string>();
		for (const column of columns) {
			for (const lane of lanesOf(root, column)) {
				const scroller = scrollerOf(lane) ?? root;
				const box = scroller.getBoundingClientRect();
				const rect = lane.getBoundingClientRect();
				if (rect.right > box.left + 24 && rect.left < box.right - 24) seen.add(column);
			}
		}
		setInView((previous) =>
			previous.size === seen.size && [...seen].every((column) => previous.has(column)) ? previous : seen,
		);
	}, [workspace, columns]);

	useEffect(() => {
		const root = workspace.current;
		if (!root) return;
		measure();
		let frame = 0;
		const later = () => {
			cancelAnimationFrame(frame);
			frame = requestAnimationFrame(measure);
		};
		root.addEventListener("scroll", later, true);
		window.addEventListener("resize", later);
		return () => {
			cancelAnimationFrame(frame);
			root.removeEventListener("scroll", later, true);
			window.removeEventListener("resize", later);
		};
	}, [workspace, measure, visible, folded]);

	function jump(column: string) {
		const root = workspace.current;
		const lane = root && lanesOf(root, column)[0];
		if (!lane) return;
		const scroller = scrollerOf(lane);
		if (!scroller) return;
		const gutter = Number.parseFloat(getComputedStyle(lane.parentElement ?? scroller).paddingLeft) || 0;
		const left = lane.getBoundingClientRect().left - scroller.getBoundingClientRect().left;
		scroller.scrollTo({ left: scroller.scrollLeft + left - gutter, behavior: "smooth" });
	}

	return (
		<nav className="column-overview" aria-label="Columns">
			{bars.map((bar) => {
				const height = Math.sqrt(bar.count / most) * 100;
				const label = `${bar.column}: ${bar.count}${bar.blocked ? `, ${bar.blocked} blocked` : ""}${bar.folded ? ", folded" : ""}`;
				return (
					<button
						key={bar.column}
						type="button"
						className={`overview-bar phase-${phaseOf(bar.column)}${inView.has(bar.column) ? " in-view" : ""}${bar.folded ? " folded" : ""}`}
						title={label}
						aria-label={label}
						aria-current={inView.has(bar.column) ? "location" : undefined}
						onClick={() => jump(bar.column)}
					>
						<span className="overview-track">
							<span className="overview-fill" style={{ height: bar.count ? `max(3px, ${height}%)` : 0 }}>
								{bar.blocked > 0 && (
									<span className="overview-blocked" style={{ height: `${(bar.blocked / bar.count) * 100}%` }} />
								)}
							</span>
						</span>
						<span className="overview-count">{bar.count}</span>
					</button>
				);
			})}
		</nav>
	);
}
