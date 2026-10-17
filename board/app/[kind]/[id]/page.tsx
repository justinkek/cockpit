import { notFound, redirect } from "next/navigation";
import { ArchivedEntity } from "@/app/archived";
import { EntityView } from "@/app/entity-view";
import { lookupEntity } from "@/lib/entity-view";
import { pageKind, pageOf } from "@/lib/shared";

export const dynamic = "force-dynamic";

const KINDS = ["ticket", "epic", "project", "sprint", "reference", "milestone", "card"];

type Props = {
	params: Promise<{ kind: string; id: string }>;
	searchParams: Promise<{ error?: string | string[] }>;
};

export default async function EntityPage({ params, searchParams }: Props) {
	const { kind, id } = await params;
	if (!KINDS.includes(kind)) notFound();
	const { error } = await searchParams;
	const failure = typeof error === "string" ? error : undefined;
	const query = failure ? `?error=${encodeURIComponent(failure)}` : "";
	const found = await lookupEntity(id);
	if ("renamed" in found) redirect(`${pageOf(found.renamed)}${query}`);
	if ("missing" in found) notFound();
	const shown = "archived" in found ? found.archived.id : found.view.entity.id;
	if (kind !== pageKind(shown)) redirect(`${pageOf(shown)}${query}`);
	if ("archived" in found) return <ArchivedEntity entity={found.archived} failure={failure} />;
	return <EntityView data={found.view} failure={failure} />;
}
