"use client";

import { flowOf, span, stagesOf } from "@/lib/metrics";
import { type Card, phaseOf } from "@/lib/shared";

function stampText(stamp: string) {
	const date = new Date(stamp);
	if (Number.isNaN(date.getTime())) return stamp;
	return date.toLocaleString(undefined, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
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
	if (stages.length === 0) return null;
	const longest = Math.max(1, ...stages.map((stage) => stage.ms ?? 0));
	return (
		<section className="timeline stages">
			<h3>Stages</h3>
			<FlowLine record={record} />
			<ol>
				{stages.map((stage, index) => (
					<li key={`${index}-${stage.column}`} className={stage.current ? "current" : undefined}>
						<span className={`dot phase-${phaseOf(stage.column)}`} aria-hidden="true" />
						<span className="stage-name">
							<span>{stage.column}</span>
							{stage.ms != null && (
								<span className="stage-bar" aria-hidden="true">
									<span
										className={`phase-${phaseOf(stage.column)}`}
										style={{ width: `${Math.max(2, (stage.ms / longest) * 100)}%` }}
									/>
								</span>
							)}
						</span>
						<span
							className="stage-span"
							title={stage.current ? "In this column now" : "Until it reached the next column"}
							suppressHydrationWarning
						>
							{stage.ms == null ? "" : span(stage.ms)}
							{stage.current && " · now"}
						</span>
						{stage.at ? (
							<time dateTime={stage.at} title={new Date(stage.at).toLocaleString()} suppressHydrationWarning>
								{stampText(stage.at)}
							</time>
						) : (
							<span />
						)}
					</li>
				))}
			</ol>
		</section>
	);
}
