const COLUMN_CARDS = [3, 5, 2, 4, 1, 3];

function Bar({ width, height = 12 }: { width: string; height?: number }) {
	return <span className="skeleton-bar" style={{ width, height }} />;
}

function Toolbar() {
	return (
		<div className="skeleton-toolbar">
			<Bar width="9rem" height={28} />
			<Bar width="6rem" height={28} />
			<Bar width="6rem" height={28} />
			<Bar width="12rem" height={28} />
		</div>
	);
}

export function BoardSkeleton({ columns = COLUMN_CARDS }: { columns?: number[] }) {
	return (
		<div className="skeleton" aria-busy="true" aria-label="Loading">
			<Toolbar />
			<div className="skeleton-columns">
				{columns.map((cards, column) => (
					<div className="skeleton-column" key={column}>
						<Bar width="60%" />
						{Array.from({ length: cards }, (_, card) => (
							<div className="skeleton-card" key={card}>
								<Bar width="85%" />
								<Bar width="40%" height={10} />
							</div>
						))}
					</div>
				))}
			</div>
		</div>
	);
}

export function ListSkeleton({ rows = 10 }: { rows?: number }) {
	return (
		<div className="skeleton" aria-busy="true" aria-label="Loading">
			<Toolbar />
			<div className="skeleton-rows">
				{Array.from({ length: rows }, (_, row) => (
					<div className="skeleton-row" key={row}>
						<Bar width="4rem" />
						<Bar width={`${40 + ((row * 17) % 40)}%`} />
						<Bar width="5rem" />
					</div>
				))}
			</div>
		</div>
	);
}

export function PlanSkeleton() {
	return (
		<div className="skeleton" aria-busy="true" aria-label="Loading">
			<Toolbar />
			<div className="skeleton-rows">
				{Array.from({ length: 10 }, (_, row) => (
					<div className="skeleton-row skeleton-plan-row" key={row}>
						<Bar width="12rem" />
						<span className="skeleton-track">
							<span
								className="skeleton-bar"
								style={{ marginLeft: `${(row * 13) % 50}%`, width: `${15 + ((row * 23) % 30)}%`, height: 14 }}
							/>
						</span>
					</div>
				))}
			</div>
		</div>
	);
}

export function PageSkeleton() {
	return (
		<div className="skeleton skeleton-page" aria-busy="true" aria-label="Loading">
			<Bar width="5rem" />
			<Bar width="55%" height={28} />
			<div className="skeleton-fields">
				{Array.from({ length: 6 }, (_, field) => (
					<div className="skeleton-row" key={field}>
						<Bar width="7rem" />
						<Bar width="10rem" />
					</div>
				))}
			</div>
			{Array.from({ length: 8 }, (_, line) => (
				<Bar width={`${60 + ((line * 29) % 40)}%`} key={line} />
			))}
		</div>
	);
}
