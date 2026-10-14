"use client";

import { flowOf, span, stagesOf } from "@/lib/metrics";
import { type Card, phaseOf } from "@/lib/shared";

export function stampText(stamp: string, now = new Date()) {
	const date = new Date(stamp);
	if (Number.isNaN(date.getTime())) return stamp;
	return date.toLocaleString(undefined, {
		weekday: "short",
		day: "numeric",
		month: "short",
		year: date.getFullYear() === now.getFullYear() ? undefined : "numeric",
		hour: "2-digit",
		minute: "2-digit",
	});
}

function Stamp({ at }: { at: string | null }) {
	if (!at) return <span className="stage-when empty">No date recorded</span>;
	return (
		<time className="stage-when" dateTime={at} title={new Date(at).toLocaleString()} suppressHydrationWarning>
			{stampText(at)}
		</time>
	);
}

function FlowLine({ record }: { record: Card }) {
	const flow = flowOf(record);
	const parts: [string, string, string][] = [];
	if (flow.lead != null) parts.push(["Lead time", span(flow.lead), "From when it was created to when it was done"]);
	if (flow.age != null) parts.push(["Open for", span(flow.age), "Since it was created"]);
	if (flow.cycle != null)
		parts.push([
			flow.lead != null ? "Cycle time" : "In progress for",
			span(flow.cycle),
			"From when it first went into dev to when it was done, or to now",
		]);
	if (parts.length === 0) return null;
	return (
		<p className="flow-line">
			{parts.map(([label, value, title]) => (
				<span key={label} title={title}>
					{label} <strong suppressHydrationWarning>{value}</strong>
				</span>
			))}
		</p>
	);
}

export function Stages({ record }: { record: Card }) {
	const stages = stagesOf(record);
	const created = record.created && !Number.isNaN(new Date(record.created).getTime()) ? record.created : null;
	if (stages.length === 0 && !created) return null;
	const first = stages[0]?.at ? new Date(stages[0].at).getTime() : null;
	const before = created && first != null ? Math.max(0, first - new Date(created).getTime()) : null;
	const longest = Math.max(1, before ?? 0, ...stages.map((stage) => stage.ms ?? 0));
	return (
		<section className="timeline stages">
			<h3>Timeline</h3>
			<FlowLine record={record} />
			<ol>
				{created && (
					<li className="stage-created">
						<span className="dot created" aria-hidden="true" />
						<span className="stage-name">
							<span className="stage-column">Created</span>
							<Stamp at={created} />
						</span>
						<span
							className="stage-span"
							title={stages[0] ? `Until it reached ${stages[0].column}` : undefined}
							suppressHydrationWarning
						>
							{before != null && stages[0] ? span(before) : ""}
						</span>
						{before != null && stages[0] && (
							<span className="stage-bar" aria-hidden="true">
								<span className="phase-idle" style={{ width: `${Math.max(2, (before / longest) * 100)}%` }} />
							</span>
						)}
					</li>
				)}
				{stages.map((stage, index) => (
					<li key={`${index}-${stage.column}`} className={stage.current ? "current" : undefined}>
						<span className={`dot phase-${phaseOf(stage.column)}`} aria-hidden="true" />
						<span className="stage-name">
							<span className="stage-column">{stage.column}</span>
							<Stamp at={stage.at} />
						</span>
						<span
							className="stage-span"
							title={stage.current ? "In this column now" : "Until it reached the next column"}
							suppressHydrationWarning
						>
							{stage.ms == null ? "" : span(stage.ms)}
							{stage.current && " · now"}
						</span>
						{stage.ms != null && (
							<span className="stage-bar" aria-hidden="true">
								<span
									className={`phase-${phaseOf(stage.column)}`}
									style={{ width: `${Math.max(2, (stage.ms / longest) * 100)}%` }}
								/>
							</span>
						)}
					</li>
				))}
			</ol>
		</section>
	);
}
