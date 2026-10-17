import { redirect } from "next/navigation";

type Props = {
	searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function SprintsPage({ searchParams }: Props) {
	const params = await searchParams;
	const query = new URLSearchParams();
	for (const [key, value] of Object.entries(params)) {
		for (const item of Array.isArray(value) ? value : value == null ? [] : [value]) query.append(key, item);
	}
	const search = query.toString();
	redirect(`/obeya${search ? `?${search}` : ""}#sprint`);
}
