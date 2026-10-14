import Link from "next/link";
import { RestoreButton } from "@/app/archived";
import { BoardError, type Card, listRecords, type RecordKind } from "@/lib/board";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<{ error?: string | string[]; restored?: string | string[] }> };

const KINDS: { kind: RecordKind; title: string }[] = [
	{ kind: "card", title: "Cards" },
	{ kind: "epic", title: "Epics" },
	{ kind: "project", title: "Projects" },
	{ kind: "sprint", title: "Sprints" },
	{ kind: "reference", title: "Reference tickets" },
];

function when(stamp: string | undefined) {
	const date = new Date(stamp ?? "");
	if (Number.isNaN(date.getTime())) return "";
	return date.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
}

export default async function ArchivePage({ searchParams }: Props) {
	const { error, restored } = await searchParams;
	let groups: { kind: RecordKind; title: string; records: Card[] }[];
	try {
		groups = await Promise.all(
			KINDS.map(async ({ kind, title }) => ({
				kind,
				title,
				records: (await listRecords(kind, true)).sort((a, b) => (b.updated ?? "").localeCompare(a.updated ?? "")),
			})),
		);
	} catch (failure) {
		if (!(failure instanceof BoardError)) throw failure;
		return <p className="notice error">{failure.message}</p>;
	}
	const shown = groups.filter((group) => group.records.length > 0);
	const total = shown.reduce((sum, group) => sum + group.records.length, 0);

	return (
		<section className="report">
			<header className="report-head">
				<h1>Archive</h1>
				<span className="count">{total}</span>
			</header>
			<p className="report-note">
				Archiving takes a record off the board without losing it, and is how anything is deleted here. Bring one back and it
				returns to the column it was in.
			</p>
			{typeof error === "string" && (
				<p className="notice error" role="alert">
					{error}
				</p>
			)}
			{typeof restored === "string" && (
				<p className="notice" role="status">
					<span>
						Brought back <Link href={`/card/${restored}`}>{restored}</Link>.
					</span>
				</p>
			)}
			{shown.length === 0 && <p className="empty">Nothing is archived.</p>}
			{shown.map((group) => (
				<div key={group.kind} className="report-card">
					<h2>
						{group.title} <span className="count">{group.records.length}</span>
					</h2>
					<ul className="record-list">
						{group.records.map((record) => (
							<li key={record.id}>
								<span className="ident">{record.id}</span>
								<Link href={`/card/${record.id}`} className="report-name">
									{record.icon && <span className="record-icon">{record.icon}</span>}
									{record.name.trim() || "(untitled)"}
								</Link>
								<span className="record-meta">
									{record.status && <span>{record.status}</span>}
									{record.updated && <span title="Archived">{when(record.updated)}</span>}
									<RestoreButton id={record.id} back="archive" label="Bring back" />
								</span>
							</li>
						))}
					</ul>
				</div>
			))}
		</section>
	);
}
