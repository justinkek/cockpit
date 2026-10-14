import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { linkChild, moveCard, unlinkChild, updateField } from "@/app/actions";
import { Content } from "@/app/content";
import { BoardError, boardColumns, FIBONACCI, findRenamed, readRecord, type Card as Stub } from "@/lib/board";

export const dynamic = "force-dynamic";

type Props = {
	params: Promise<{ id: string }>;
	searchParams: Promise<{ error?: string }>;
};

function Row({ label, children }: { label: string; children: React.ReactNode }) {
	return (
		<>
			<dt>{label}</dt>
			<dd>{children}</dd>
		</>
	);
}

function StubLinks({ ids }: { ids: string[] }) {
	if (ids.length === 0) return <span className="empty">none</span>;
	return (
		<>
			{ids.map((id) => (
				<Link key={id} href={`/card/${id}`} className="chip">
					{id}
				</Link>
			))}
		</>
	);
}

export default async function StubPage({ params, searchParams }: Props) {
	const { id } = await params;
	const { error } = await searchParams;
	let stub: Stub;
	try {
		stub = await readRecord(id);
	} catch (failure) {
		if (!(failure instanceof BoardError)) throw failure;
		const renamed = await findRenamed(id);
		if (renamed) redirect(`/card/${renamed}`);
		notFound();
	}

	return (
		<article className="stub">
			<h1>{stub.name}</h1>
			<p className="meta">
				<span>{stub.id}</span>
				<span>{stub.type}</span>
				<span>{stub.status}</span>
			</p>
			{error && <p className="notice error">{error}</p>}

			<form action={moveCard} className="edit">
				<input type="hidden" name="id" value={stub.id} />
				<label htmlFor="status">Status</label>
				<select id="status" name="status" defaultValue={stub.status}>
					{!boardColumns(stub.id.startsWith("EPIC-") ? "epic" : "card").includes(stub.status) && (
						<option disabled>{stub.status}</option>
					)}
					{boardColumns(stub.id.startsWith("EPIC-") ? "epic" : "card").map((column) => (
						<option key={column}>{column}</option>
					))}
				</select>
				<button type="submit">Move</button>
			</form>

			<form action={updateField} className="edit">
				<input type="hidden" name="id" value={stub.id} />
				<input type="hidden" name="field" value="complexity" />
				<label htmlFor="complexity">Complexity</label>
				<select id="complexity" name="value" defaultValue={stub.complexity ?? ""}>
					<option value="" disabled>
						not set
					</option>
					{FIBONACCI.map((points) => (
						<option key={points} value={points}>
							{points}
						</option>
					))}
				</select>
				<button type="submit">Set</button>
			</form>

			<form action={updateField} className="edit">
				<input type="hidden" name="id" value={stub.id} />
				<input type="hidden" name="field" value="epic" />
				<label htmlFor="epic">Epic</label>
				<input id="epic" name="value" defaultValue={stub.epic ?? ""} />
				<button type="submit">Set</button>
			</form>

			<section className="links">
				<h2>Dependent on</h2>
				<ul>
					{(stub.dependent_on ?? []).map((child) => (
						<li key={child}>
							<Link href={`/card/${child}`} className="chip">
								{child}
							</Link>
							<form action={unlinkChild}>
								<input type="hidden" name="id" value={stub.id} />
								<input type="hidden" name="child" value={child} />
								<button type="submit" className="quiet">
									Unlink
								</button>
							</form>
						</li>
					))}
				</ul>
				<form action={linkChild} className="edit">
					<input type="hidden" name="id" value={stub.id} />
					<label htmlFor="child">Add child</label>
					<input id="child" name="child" placeholder="FEAT-12" required pattern="[A-Za-z][A-Za-z0-9]*-[0-9]+" />
					<button type="submit">Link</button>
				</form>
			</section>

			<dl className="facts">
				<Row label="Dependency for">
					<StubLinks ids={stub.dependency_for ?? []} />
				</Row>
				<Row label="Claimed by">{stub.session ?? <span className="empty">nobody</span>}</Row>
				<Row label="Cost">
					{stub.cost_usd != null ? `$${stub.cost_usd}` : <span className="empty">-</span>}
					{stub.tokens_k != null && ` · ${stub.tokens_k}k tokens`}
				</Row>
				<Row label="Created">{stub.created}</Row>
				{Object.entries(stub.dates ?? {}).map(([column, stamp]) => (
					<Row key={column} label={`Date: ${column}`}>
						{stamp}
					</Row>
				))}
			</dl>

			<Content id={stub.id} body={stub.body} />
		</article>
	);
}
