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

export function ArchivedEntity({ entity, failure }: { entity: Card; failure?: string }) {
	return (
		<article className="stub">
			{entity.icon && <span className="page-icon">{entity.icon}</span>}
			<h1 className="archived-title">{entity.name}</h1>
			<p className="meta">
				<span>{entity.id}</span>
				{entity.status && <span>{entity.status}</span>}
			</p>
			{failure && (
				<p className="notice error" role="alert">
					{failure}
				</p>
			)}
			<p className="notice archived-notice">
				<span>
					{entity.id} is archived, so it is off the board and nothing can change it. Bring it back to work on it again,
					or see everything archived on the <Link href="/archive">Archive</Link> page.
				</span>
				<RestoreButton id={entity.id} />
			</p>
		</article>
	);
}
