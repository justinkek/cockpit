import { Settings } from "@/app/settings";
import { type Break, BoardError, boardTracks, type Card, listRecords, readBreaks } from "@/lib/board";

export const dynamic = "force-dynamic";

export default async function SettingsPage() {
	let projects: Card[];
	let tracks: number;
	let breaks: Break[];
	try {
		[projects, tracks, breaks] = await Promise.all([listRecords("project"), boardTracks(), readBreaks()]);
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return <p className="notice error">{error.message}</p>;
	}
	return (
		<Settings
			tracks={tracks}
			breaks={breaks}
			projects={projects.map(({ id, name, tracks, status }) => ({ id, name, tracks, status }))}
		/>
	);
}
