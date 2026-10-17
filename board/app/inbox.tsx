"use client";

import Link from "next/link";
import { useMemo, useState, useTransition } from "react";
import { markInboxRead } from "@/app/actions";
import { INBOX_READ, itemHref, itemKey } from "@/app/notify";
import { ago, type Inbox, type InboxItem } from "@/lib/shared";

type Filter = "all" | InboxItem["kind"];

const FILTERS: { value: Filter; label: string }[] = [
	{ value: "all", label: "All" },
	{ value: "comment", label: "Comments" },
	{ value: "waiting", label: "Waiting on you" },
	{ value: "blocked", label: "Blocked" },
];

function Headline({ item }: { item: InboxItem }) {
	const card = (
		<>
			<span className="ident">{item.id}</span> {item.name}
		</>
	);
	if (item.kind === "comment") {
		return (
			<>
				<strong>{item.author}</strong> {item.resolved ? "commented on a resolved thread on" : "commented on"} {card}
			</>
		);
	}
	if (item.kind === "blocked") return <>{card} is blocked</>;
	return (
		<>
			{card} is waiting for you in <strong>{item.status}</strong>
		</>
	);
}

export function InboxList({ inbox }: { inbox: Inbox }) {
	const [filter, setFilter] = useState<Filter>("all");
	const [unreadOnly, setUnreadOnly] = useState(false);
	const [readUpTo, setReadUpTo] = useState<string | null>(null);
	const [error, setError] = useState("");
	const [busy, startTransition] = useTransition();

	const items = useMemo(
		() =>
			inbox.items.map((item) =>
				readUpTo && item.unread && Date.parse(item.at) <= Date.parse(readUpTo) ? { ...item, unread: false } : item,
			),
		[inbox.items, readUpTo],
	);
	const unread = readUpTo ? items.filter((item) => item.unread).length : inbox.unread;
	const shown = items.filter((item) => (filter === "all" || item.kind === filter) && (!unreadOnly || item.unread));

	function markRead() {
		const stamp = inbox.now;
		setReadUpTo(stamp);
		setError("");
		startTransition(async () => {
			const result = await markInboxRead(stamp);
			if (result.error) {
				setReadUpTo(null);
				setError(`Could not mark the inbox read: ${result.error}`);
				return;
			}
			window.dispatchEvent(new Event(INBOX_READ));
		});
	}

	return (
		<section className="inbox">
			<header className="inbox-head">
				<h1>Inbox {unread > 0 && <span className="count">{unread} unread</span>}</h1>
				<span className="inbox-actions">
					<Link href="/settings#notifications" className="settings-pointer">
						Notifications in Settings
					</Link>
					<button type="button" onClick={markRead} disabled={busy || unread === 0}>
						Mark all read
					</button>
				</span>
			</header>
			<div className="inbox-filters">
				<span className="segmented" role="group" aria-label="Show">
					{FILTERS.map((option) => (
						<button
							key={option.value}
							type="button"
							className={filter === option.value ? "on" : undefined}
							aria-pressed={filter === option.value}
							onClick={() => setFilter(option.value)}
						>
							{option.label}
						</button>
					))}
				</span>
				<button
					type="button"
					className={`chip-toggle${unreadOnly ? " on" : ""}`}
					aria-pressed={unreadOnly}
					onClick={() => setUnreadOnly((current) => !current)}
				>
					Unread only
				</button>
			</div>
			{error && (
				<p className="notice error" role="alert">
					{error}
				</p>
			)}
			{shown.length === 0 ? (
				<p className="empty inbox-empty">
					{unreadOnly || filter !== "all" ? "Nothing here with these filters." : "Nothing in the inbox."}
				</p>
			) : (
				<ol className="inbox-items">
					{shown.map((item) => (
						<li key={itemKey(item)} className={`inbox-item ${item.kind}${item.unread ? " unread" : ""}`}>
							<span className="inbox-dot" aria-label={item.unread ? "Unread" : undefined} />
							<Link href={itemHref(item)} className="inbox-link">
								<span className="inbox-line">
									<span className="inbox-title">
										<Headline item={item} />
									</span>
									<time dateTime={item.at} title={new Date(item.at).toLocaleString()} suppressHydrationWarning>
										{ago(item.at)}
									</time>
								</span>
								{item.kind === "comment" && item.anchor && <span className="inbox-quote">{item.anchor}</span>}
								{item.text && <span className="inbox-text">{item.text}</span>}
							</Link>
						</li>
					))}
				</ol>
			)}
			{inbox.items.length >= 100 && <p className="empty inbox-empty">Showing the newest 100.</p>}
		</section>
	);
}
