import type { Remaining } from "@/lib/plan";

function plural(count: number, one: string, many: string) {
	return `${count} ${count === 1 ? one : many}`;
}

export function tdEstimateText(remaining: Remaining) {
	return remaining.estimated > 0 ? String(remaining.estimate) : "-";
}

export function trComplexityText(remaining: Remaining) {
	return remaining.sized > 0 ? String(remaining.complexity) : "-";
}

export function sizedText(remaining: Remaining) {
	return `${remaining.sized} of ${plural(remaining.tickets, "ticket", "tickets")} sized`;
}

export function estimatesTitle(remaining: Remaining) {
	if (remaining.tickets === 0) return "No open tickets, so no TD estimate or TR complexity";
	const parts = [
		remaining.estimated > 0
			? `TD estimate ${remaining.estimate} pts across ${plural(remaining.estimated, "open ticket", "open tickets")}`
			: "No open ticket has a TD estimate",
		remaining.sized > 0
			? `TR complexity ${remaining.complexity} pts, ${sizedText(remaining)}`
			: `TR complexity: ${sizedText(remaining)}`,
	];
	if (remaining.unsized > 0)
		parts.push(
			`${plural(remaining.unsized, "open ticket has", "open tickets have")} neither and ${remaining.unsized === 1 ? "is" : "are"} left out of the plan`,
		);
	return parts.join("; ");
}

export function EstimatePill({ remaining }: { remaining: Remaining }) {
	return (
		<span className="pill estimates" title={estimatesTitle(remaining)}>
			TD {tdEstimateText(remaining)} · TR {trComplexityText(remaining)}
			{remaining.tickets > 0 && (
				<span className="estimates-sized">
					{" "}
					({remaining.sized}/{remaining.tickets})
				</span>
			)}
		</span>
	);
}

export function EstimateFacts({ remaining, left = false }: { remaining: Remaining; left?: boolean }) {
	return (
		<dl className="props estimate-facts" title={estimatesTitle(remaining)}>
			{left && (
				<>
					<dt>Points left</dt>
					<dd>{remaining.points} pts</dd>
				</>
			)}
			<dt>TD estimate</dt>
			<dd>{remaining.estimated > 0 ? `${remaining.estimate} pts` : <span className="empty">-</span>}</dd>
			<dt>TR complexity</dt>
			<dd>
				{remaining.sized > 0 ? `${remaining.complexity} pts` : <span className="empty">-</span>}
				{remaining.tickets > 0 && <span className="estimates-sized"> · {sizedText(remaining)}</span>}
			</dd>
			{remaining.unsized > 0 && (
				<>
					<dt>Unsized</dt>
					<dd>{plural(remaining.unsized, "open ticket", "open tickets")} with neither, left out of the plan</dd>
				</>
			)}
		</dl>
	);
}
