import { Settings } from "@/app/settings";
import { BoardError, readAllViews, type SavedView } from "@/lib/board";

export const dynamic = "force-dynamic";

export default async function SettingsPage() {
	let views: SavedView[];
	try {
		views = await readAllViews();
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return <p className="notice error">{error.message}</p>;
	}
	return <Settings views={views} />;
}
