import { Settings } from "@/app/settings";
import {
	type Break,
	BoardError,
	boardTracks,
	type Card,
	listRecords,
	readAllViews,
	readBreaks,
	type SavedView,
} from "@/lib/board";

export const dynamic = "force-dynamic";

export default async function SettingsPage() {
	let projects: Card[];
	let tracks: number;
	let breaks: Break[];
	let views: SavedView[];
	try {
		[projects, tracks, breaks, views] = await Promise.all([
			listRecords("project"),
			boardTracks(),
			readBreaks(),
			readAllViews(),
		]);
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return <p className="notice error">{error.message}</p>;
	}
	return (
		<Settings
			tracks={tracks}
			breaks={breaks}
			views={views}
			projects={projects.map(({ id, name, tracks, status }) => ({ id, name, tracks, status }))}
		/>
	);
}
