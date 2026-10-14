import { byPoints, type Progress, progressShare, progressTitle } from "@/lib/metrics";

export function ProgressMeter({ progress, wide = false }: { progress: Progress; wide?: boolean }) {
	const share = progressShare(progress);
	const percent = Math.round(share * 100);
	return (
		<span
			className={`progress${wide ? " wide" : ""}${progress.total > 0 && progress.done === progress.total ? " complete" : ""}`}
			title={progressTitle(progress)}
		>
			<span
				className="progress-track"
				role="progressbar"
				aria-valuemin={0}
				aria-valuemax={100}
				aria-valuenow={percent}
				aria-label={progressTitle(progress)}
			>
				<span style={{ width: `${percent}%` }} />
			</span>
			<span className="progress-text">
				{progress.total === 0 ? "No cards" : `${progress.done}/${progress.total}`}
				{wide && progress.total > 0 && (
					<span className="progress-percent">
						{" "}
						· {percent}%{byPoints(progress) && " of points"}
					</span>
				)}
			</span>
		</span>
	);
}
