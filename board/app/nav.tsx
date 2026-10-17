"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { onBoardChange } from "@/app/live";
import { announce, INBOX_READ, itemKey } from "@/app/notify";
import type { InboxItem } from "@/lib/shared";

const LINKS = [
	{ href: "/obeya", label: "Obeya" },
	{ href: "/projects", label: "Projects" },
	{ href: "/plan", label: "Plan" },
	{ href: "/epics", label: "Epics" },
	{ href: "/sprints", label: "Sprints" },
	{ href: "/", label: "Cards" },
	{ href: "/references", label: "References" },
	{ href: "/archive", label: "Archive" },
];

function useUnread() {
	const [unread, setUnread] = useState(0);
	const known = useRef<Set<string> | null>(null);

	useEffect(() => {
		let asked = 0;
		async function check() {
			const ticket = ++asked;
			try {
				const response = await fetch("/inbox-count", { cache: "no-store" });
				if (!response.ok) return;
				const answer: { unread: number; items: InboxItem[] } = await response.json();
				if (ticket !== asked) return;
				setUnread(answer.unread);
				const keys = answer.items.map(itemKey);
				if (known.current) {
					const fresh = answer.items.filter((item) => !known.current?.has(itemKey(item)));
					for (const item of fresh.slice(0, 3)) announce(item);
				}
				known.current = new Set([...(known.current ?? []), ...keys]);
			} catch {}
		}
		function read() {
			setUnread(0);
			check();
		}
		check();
		const stop = onBoardChange(check);
		window.addEventListener(INBOX_READ, read);
		return () => {
			stop();
			window.removeEventListener(INBOX_READ, read);
		};
	}, []);

	return unread;
}

export function Nav() {
	const pathname = usePathname();
	const unread = useUnread();
	return (
		<nav className="nav">
			{LINKS.map((link) => (
				<Link key={link.href} href={link.href} className={pathname === link.href ? "on" : undefined}>
					{link.label}
				</Link>
			))}
			<Link
				href="/inbox"
				className={pathname === "/inbox" ? "on" : undefined}
				title={unread > 0 ? `${unread} unread in the inbox` : "Inbox"}
			>
				Inbox
				{unread > 0 && <span className="badge">{unread > 99 ? "99+" : unread}</span>}
			</Link>
		</nav>
	);
}
