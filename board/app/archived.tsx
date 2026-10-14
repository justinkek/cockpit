import Link from "next/link";
import { submitUnarchive } from "@/app/actions";
import type { Card } from "@/lib/shared";

export function RestoreButton({ id, back, label = "Bring it back" }: { id: string; back?: "archive"; label?: string }) {
	return (
		<form action={submitUnarchive} className="restore-form">
			<input type="hidden" name="id" value={id} />
			{back && <input type="hidden" name="back" value={back} />}
			<button type="submit">{label}</button>
		</form>
	);
}

export function ArchivedRecord({ record, failure }: { record: Card; failure?: string }) {
	return (
		<article className="stub">
			{record.icon && <span className="page-icon">{record.icon}</span>}
			<h1 className="archived-title">{record.name}</h1>
			<p className="meta">
				<span>{record.id}</span>
				{record.status && <span>{record.status}</span>}
			</p>
			{failure && (
				<p className="notice error" role="alert">
					{failure}
				</p>
			)}
			<p className="notice archived-notice">
				<span>
					{record.id} is archived, so it is off the board and nothing can change it. Bring it back to work on it again, or
					see everything archived on the <Link href="/archive">Archive</Link> page.
				</span>
				<RestoreButton id={record.id} />
			</p>
		</article>
	);
}
