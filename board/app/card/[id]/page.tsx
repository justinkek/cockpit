import { notFound, redirect } from "next/navigation";
import { ArchivedEntity } from "@/app/archived";
import { EntityView } from "@/app/entity-view";
import { lookupEntity } from "@/lib/entity-view";

export const dynamic = "force-dynamic";

type Props = {
	params: Promise<{ id: string }>;
	searchParams: Promise<{ error?: string | string[] }>;
};

export default async function CardPage({ params, searchParams }: Props) {
	const { id } = await params;
	const { error } = await searchParams;
	const failure = typeof error === "string" ? error : undefined;
	const found = await lookupEntity(id);
	if ("archived" in found) return <ArchivedEntity entity={found.archived} failure={failure} />;
	if ("renamed" in found) redirect(`/card/${found.renamed}`);
	if ("missing" in found) notFound();
	return <EntityView data={found.view} failure={failure} />;
}
