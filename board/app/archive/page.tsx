import Link from "next/link";
import { RestoreButton } from "@/app/archived";
import { BoardError, type Card, listEntities, type EntityKind, pageOf } from "@/lib/board";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<{ error?: string | string[]; restored?: string | string[] }> };

const KINDS: { kind: EntityKind; title: string }[] = [
	{ kind: "card", title: "Tickets" },
	{ kind: "epic", title: "Epics" },
	{ kind: "project", title: "Projects" },
	{ kind: "sprint", title: "Sprints" },
	{ kind: "reference", title: "Reference tickets" },
	{ kind: "milestone", title: "Milestones" },
];

function when(stamp: string | undefined) {
	const date = new Date(stamp ?? "");
	if (Number.isNaN(date.getTime())) return "";
	return date.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
}

export default async function ArchivePage({ searchParams }: Props) {
	const { error, restored } = await searchParams;
	let groups: { kind: EntityKind; title: string; entities: Card[] }[];
	try {
		groups = await Promise.all(
			KINDS.map(async ({ kind, title }) => ({
				kind,
				title,
				entities: (await listEntities(kind, true)).sort((a, b) => (b.updated ?? "").localeCompare(a.updated ?? "")),
			})),
		);
	} catch (failure) {
		if (!(failure instanceof BoardError)) throw failure;
		return <p className="notice error">{failure.message}</p>;
	}
	const shown = groups.filter((group) => group.entities.length > 0);
	const total = shown.reduce((sum, group) => sum + group.entities.length, 0);

	return (
		<section className="report">
			<header className="report-head">
				<h1>Archive</h1>
				<span className="count">{total}</span>
			</header>
			<p className="report-note">
				Archiving takes an entity off the board without losing it, and is how anything is deleted here. Bring one back
				and it returns to the column it was in.
			</p>
			{typeof error === "string" && (
				<p className="notice error" role="alert">
					{error}
				</p>
			)}
			{typeof restored === "string" && (
				<p className="notice" role="status">
					<span>
						Brought back <Link href={pageOf(restored)}>{restored}</Link>.
					</span>
				</p>
			)}
			{shown.length === 0 && <p className="empty">Nothing is archived.</p>}
			{shown.map((group) => (
				<div key={group.kind} className="report-card">
					<h2>
						{group.title} <span className="count">{group.entities.length}</span>
					</h2>
					<ul className="entity-list">
						{group.entities.map((entity) => (
							<li key={entity.id}>
								<span className="ident">{entity.id}</span>
								<Link href={pageOf(entity.id)} className="report-name">
									{entity.icon && <span className="entity-icon">{entity.icon}</span>}
									{entity.name.trim() || "(untitled)"}
								</Link>
								<span className="entity-meta">
									{entity.status && <span>{entity.status}</span>}
									{entity.updated && <span title="Archived">{when(entity.updated)}</span>}
									<RestoreButton id={entity.id} back="archive" label="Bring back" />
								</span>
							</li>
						))}
					</ul>
				</div>
			))}
		</section>
	);
}
