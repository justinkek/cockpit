import type { Estimates, Remaining } from "@/lib/plan";

function plural(count: number, one: string, many: string) {
	return `${count} ${count === 1 ? one : many}`;
}

function figureOr(count: number, points: number) {
	return count > 0 ? String(points) : "-";
}

export function tdEstimateText({ total, left }: Estimates) {
	return `${figureOr(total.estimated, total.estimate)} total · ${figureOr(left.estimated, left.estimate)} left`;
}

export function trComplexityText({ total, left }: Estimates) {
	return `${figureOr(total.sized, total.complexity)} total · ${figureOr(left.sized, left.complexity)} left`;
}

export function sizedText(remaining: Remaining) {
	return `${remaining.sized} of ${plural(remaining.tickets, "open ticket", "open tickets")} sized`;
}

export function estimatesTitle(remaining: Remaining) {
	if (remaining.tickets === 0) return "No open tickets, so no TD estimate or TR complexity left";
	const parts = [
		remaining.estimated > 0
			? `TD estimate ${remaining.estimate} pts left across ${plural(remaining.estimated, "open ticket", "open tickets")}`
			: "No open ticket has a TD estimate",
		remaining.sized > 0
			? `TR complexity ${remaining.complexity} pts left, ${sizedText(remaining)}`
			: `TR complexity: ${sizedText(remaining)}`,
	];
	if (remaining.unsized > 0)
		parts.push(
			`${plural(remaining.unsized, "open ticket has", "open tickets have")} neither and ${remaining.unsized === 1 ? "is" : "are"} left out of the plan`,
		);
	return parts.join("; ");
}

function totalsTitle(estimates: Estimates) {
	const { total } = estimates;
	if (total.tickets === 0) return "No tickets, so no TD estimate or TR complexity";
	return `Across all ${plural(total.tickets, "ticket", "tickets")}, deprioritised ones left out: TD estimate ${tdEstimateText(estimates)}, TR complexity ${trComplexityText(estimates)}. ${estimatesTitle(estimates.left)}`;
}

function pillText(counted: number, total: number, countedLeft: number, totalLeft: number) {
	return counted > 0 ? `${total}, ${figureOr(countedLeft, totalLeft)} left` : "-";
}

export function EstimatePill({ estimates }: { estimates: Estimates }) {
	const { left } = estimates;
	return (
		<span className="pill estimates" title={totalsTitle(estimates)}>
			TD {pillText(estimates.total.estimated, estimates.total.estimate, left.estimated, left.estimate)} · TR{" "}
			{pillText(estimates.total.sized, estimates.total.complexity, left.sized, left.complexity)}
			{left.tickets > 0 && (
				<span className="estimates-sized">
					{" "}
					({left.sized}/{left.tickets})
				</span>
			)}
		</span>
	);
}

export function EstimateFacts({ estimates, left = false }: { estimates: Estimates; left?: boolean }) {
	const remaining = estimates.left;
	return (
		<dl className="props estimate-facts" title={totalsTitle(estimates)}>
			{left && (
				<>
					<dt>Points left</dt>
					<dd>{remaining.points} pts</dd>
				</>
			)}
			<dt>TD estimate</dt>
			<dd>{tdEstimateText(estimates)}</dd>
			<dt>TR complexity</dt>
			<dd>
				{trComplexityText(estimates)}
				{remaining.tickets > 0 && <span className="estimates-sized"> ({sizedText(remaining)})</span>}
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
