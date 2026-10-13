"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const LINKS = [
	{ href: "/", label: "Cards" },
	{ href: "/epics", label: "Epics" },
];

export function Nav() {
	const pathname = usePathname();
	return (
		<nav className="nav">
			{LINKS.map((link) => (
				<Link key={link.href} href={link.href} className={pathname === link.href ? "on" : undefined}>
					{link.label}
				</Link>
			))}
		</nav>
	);
}
