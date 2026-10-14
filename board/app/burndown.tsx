"use client";

import { useState } from "react";
import type { Burndown } from "@/lib/metrics";

const WIDTH = 600;
const HEIGHT = 200;

function dayLabel(day: string, long = false) {
	const [year, month, date] = day.split("-").map(Number);
	return new Date(year, month - 1, date).toLocaleDateString(undefined, {
		weekday: "short",
		day: "numeric",
		month: long ? "short" : undefined,
	});
}

function pointLabel(burndown: Burndown, index: number) {
	return index === 0 ? "Sprint start" : `End of ${dayLabel(burndown.days[index - 1], true)}`;
}

function amount(value: number) {
	return Number.isInteger(value) ? String(value) : value.toFixed(1);
}

export function BurndownChart({
	burndown,
	unit,
	compact = false,
}: {
	burndown: Burndown;
	unit: string;
	compact?: boolean;
}) {
	const [at, setAt] = useState<number | null>(null);
	const steps = burndown.days.length;
	if (steps === 0)
		return <p className="empty">This sprint has no start and end dates, so it has nothing to burn down over.</p>;
	const top = Math.max(1, burndown.total, ...burndown.remaining.map((value) => value ?? 0));
	const x = (index: number) => (index / steps) * WIDTH;
	const y = (value: number) => HEIGHT - (value / top) * HEIGHT;
	const ideal = burndown.ideal.map((value, index) => `${x(index)},${y(value)}`).join(" ");
	const known = burndown.remaining.flatMap((value, index) => (value == null ? [] : [[index, value] as const]));
	const actual = known.map(([index, value]) => `${x(index)},${y(value)}`).join(" ");
	const last = known.at(-1);
	const labelEvery = Math.ceil(steps / (compact ? 4 : 8));
	const shown = at ?? null;

	function pick(event: React.PointerEvent<HTMLDivElement>) {
		const box = event.currentTarget.getBoundingClientRect();
		const share = Math.min(1, Math.max(0, (event.clientX - box.left) / box.width));
		setAt(Math.round(share * steps));
	}

	function step(event: React.KeyboardEvent<HTMLDivElement>) {
		if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
		event.preventDefault();
		const from = at ?? (last ? last[0] : 0);
		setAt(Math.min(steps, Math.max(0, from + (event.key === "ArrowRight" ? 1 : -1))));
	}

	return (
		<figure className={`burndown${compact ? " compact" : ""}`}>
			<figcaption className="chart-legend">
				<span>
					<span className="key remaining" aria-hidden="true" />
					{unit} left
				</span>
				<span>
					<span className="key ideal" aria-hidden="true" />
					Ideal
				</span>
			</figcaption>
			<div className="burndown-frame">
				<span className="axis-y">
					<span>{amount(top)}</span>
					<span>0</span>
				</span>
				<div
					className="burndown-plot"
					role="img"
					aria-label={`Burndown of ${burndown.total} ${unit} over ${steps} working days${last ? `, ${amount(last[1])} left` : ""}`}
					tabIndex={0}
					onPointerMove={pick}
					onPointerDown={pick}
					onPointerLeave={() => setAt(null)}
					onKeyDown={step}
					onBlur={() => setAt(null)}
				>
					<svg viewBox={`0 0 ${WIDTH} ${HEIGHT}`} preserveAspectRatio="none" aria-hidden="true">
						{[0.25, 0.5, 0.75].map((share) => (
							<line key={share} className="grid" x1={0} x2={WIDTH} y1={HEIGHT * share} y2={HEIGHT * share} />
						))}
						<line className="baseline" x1={0} x2={WIDTH} y1={HEIGHT} y2={HEIGHT} />
						<polyline className="ideal" points={ideal} />
						{known.length > 1 && <polyline className="remaining" points={actual} />}
					</svg>
					{last && (
						<span
							className="end-label"
							style={{ left: `${(last[0] / steps) * 100}%`, top: `${(y(last[1]) / HEIGHT) * 100}%` }}
						>
							{amount(last[1])}
						</span>
					)}
					{shown != null && (
						<>
							<span className="crosshair" style={{ left: `${(shown / steps) * 100}%` }} />
							{burndown.remaining[shown] != null && (
								<span
									className="marker"
									style={{
										left: `${(shown / steps) * 100}%`,
										top: `${(y(burndown.remaining[shown] ?? 0) / HEIGHT) * 100}%`,
									}}
								/>
							)}
							<span
								className={`chart-tip${shown > steps / 2 ? " flip" : ""}`}
								style={{ left: `${(shown / steps) * 100}%` }}
							>
								<span className="tip-title">{pointLabel(burndown, shown)}</span>
								<span className="tip-row">
									<span className="key remaining" aria-hidden="true" />
									<strong>{burndown.remaining[shown] == null ? "-" : amount(burndown.remaining[shown] ?? 0)}</strong>
									{unit.toLowerCase()} left
								</span>
								<span className="tip-row">
									<span className="key ideal" aria-hidden="true" />
									<strong>{amount(burndown.ideal[shown])}</strong>
									ideal
								</span>
							</span>
						</>
					)}
				</div>
				<span className="axis-x">
					{burndown.days.map((day, index) =>
						index % labelEvery === labelEvery - 1 || index === steps - 1 ? (
							<span key={day} style={{ left: `${((index + 1) / steps) * 100}%` }}>
								{dayLabel(day)}
							</span>
						) : null,
					)}
				</span>
			</div>
			{!compact && (
				<details className="chart-numbers">
					<summary>Show the numbers</summary>
					<table>
						<thead>
							<tr>
								<th scope="col">When</th>
								<th scope="col" className="numeric">
									{unit} left
								</th>
								<th scope="col" className="numeric">
									Ideal
								</th>
							</tr>
						</thead>
						<tbody>
							{burndown.ideal.map((ideal, index) => (
								<tr key={pointLabel(burndown, index)}>
									<th scope="row">{pointLabel(burndown, index)}</th>
									<td className="numeric">
										{burndown.remaining[index] == null ? "-" : amount(burndown.remaining[index] ?? 0)}
									</td>
									<td className="numeric">{amount(ideal)}</td>
								</tr>
							))}
						</tbody>
					</table>
				</details>
			)}
		</figure>
	);
}
