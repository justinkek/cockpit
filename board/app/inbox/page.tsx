import { InboxList } from "@/app/inbox";
import { BoardError, type Inbox, readInbox } from "@/lib/board";

export const dynamic = "force-dynamic";

export default async function InboxPage() {
	let inbox: Inbox;
	try {
		inbox = await readInbox();
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		return <p className="notice error">{error.message}</p>;
	}
	return <InboxList inbox={inbox} />;
}
