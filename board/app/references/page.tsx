import Link from "next/link";
import { NewOther } from "@/app/new-entity";
import { BoardError, type Card, DOMAINS, listEntities, pageOf } from "@/lib/board";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<{ error?: string | string[] }> };

export default async function ReferencesPage({ searchParams }: Props) {
	const { error } = await searchParams;
	let references: Card[];
	try {
		references = await listEntities("reference");
	} catch (failure) {
		if (!(failure instanceof BoardError)) throw failure;
		return <p className="notice error">{failure.message}</p>;
	}

	const domains: string[] = [...DOMAINS, ""];
	const groups = domains
		.map((domain) => ({
			domain,
			references: references
				.filter(
					(reference) =>
						(reference.domain ?? "") === domain || (domain === "" && !domains.includes(reference.domain ?? "")),
				)
				.sort(
					(a, b) =>
						(a.points ?? Number.POSITIVE_INFINITY) - (b.points ?? Number.POSITIVE_INFINITY) ||
						a.name.localeCompare(b.name),
				),
		}))
		.filter((group) => group.references.length > 0);

	return (
		<section className="report">
			<header className="report-head">
				<h1>Reference tickets</h1>
				<span className="count">{references.length}</span>
				<span className="spacer" />
				<NewOther kind="reference" />
			</header>
			<p className="report-note">The changes a new ticket's complexity is compared against when it is sized.</p>
			{typeof error === "string" && (
				<p className="notice error" role="alert">
					{error}
				</p>
			)}
			{groups.length === 0 && <p className="empty">No reference ticket is on the board yet.</p>}
			{groups.map((group) => (
				<div key={group.domain} className="report-card">
					<h2>
						{group.domain || "No domain"} <span className="count">{group.references.length}</span>
					</h2>
					<ul className="entity-list">
						{group.references.map((reference) => (
							<li key={reference.id}>
								<span className="ident">{reference.id}</span>
								<Link href={pageOf(reference.id)} className="report-name" title={reference.description ?? undefined}>
									{reference.icon && <span className="entity-icon">{reference.icon}</span>}
									{reference.name}
								</Link>
								<span className="entity-meta">
									{reference.stack && <span>{reference.stack}</span>}
									{reference.card && <span className="ident">{reference.card}</span>}
									<span className="pill reference-points" title="Points">
										{reference.points ?? "-"}
									</span>
								</span>
							</li>
						))}
					</ul>
				</div>
			))}
		</section>
	);
}
