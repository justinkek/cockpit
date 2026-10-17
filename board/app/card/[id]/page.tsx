import { notFound, redirect } from "next/navigation";
import { ArchivedRecord } from "@/app/archived";
import { RecordView } from "@/app/record-view";
import { lookupRecord } from "@/lib/record-view";

export const dynamic = "force-dynamic";

type Props = {
	params: Promise<{ id: string }>;
	searchParams: Promise<{ error?: string | string[] }>;
};

export default async function CardPage({ params, searchParams }: Props) {
	const { id } = await params;
	const { error } = await searchParams;
	const failure = typeof error === "string" ? error : undefined;
	const found = await lookupRecord(id);
	if ("archived" in found) return <ArchivedRecord record={found.archived} failure={failure} />;
	if ("renamed" in found) redirect(`/card/${found.renamed}`);
	if ("missing" in found) notFound();
	return <RecordView data={found.view} failure={failure} />;
}
