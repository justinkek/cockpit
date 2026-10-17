import type { Metadata, Viewport } from "next";
import Link from "next/link";
import { LiveUpdates } from "@/app/live";
import { Nav, SettingsLink } from "@/app/nav";
import { ThemeSync } from "@/app/theme";
import { THEME_SCRIPT } from "@/lib/theme";
import "./globals.css";

export const metadata: Metadata = { title: "Cockpit board" };
export const viewport: Viewport = { width: "device-width", initialScale: 1 };

export default function RootLayout({ children }: { children: React.ReactNode }) {
	return (
		<html lang="en" suppressHydrationWarning>
			<head>
				<script dangerouslySetInnerHTML={{ __html: THEME_SCRIPT }} />
			</head>
			<body>
				<header className="masthead">
					<Link href="/" className="brand">
						<span className="brand-mark" aria-hidden="true" />
						<span className="brand-name">Cockpit</span>
					</Link>
					<Nav />
					<LiveUpdates />
					<SettingsLink />
					<ThemeSync />
				</header>
				<main>{children}</main>
			</body>
		</html>
	);
}
