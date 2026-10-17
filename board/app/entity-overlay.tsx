"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { loadEntityView } from "@/app/actions";
import { ArchivedEntity } from "@/app/archived";
import { confirmDiscard } from "@/app/content";
import { useKeys } from "@/app/keys";
import { onBoardChange } from "@/app/live";
import { type OverlayHost, EntityView } from "@/app/entity-view";
import { typingIn } from "@/app/toast";
import type { EntityLookup } from "@/lib/entity-view";

const PUSHED = "cockpitOpened";

function openInUrl() {
	return new URLSearchParams(window.location.search).get("open")?.toUpperCase() || null;
}

function urlWith(id: string | null) {
	const url = new URL(window.location.href);
	if (id) url.searchParams.set("open", id);
	else url.searchParams.delete("open");
	return url;
}

export function useOpenEntity() {
	const [openId, setOpenId] = useState<string | null>(null);
	const shown = useRef(openId);
	shown.current = openId;

	useEffect(() => {
		const read = () => setOpenId(openInUrl());
		read();
		window.addEventListener("popstate", read);
		return () => window.removeEventListener("popstate", read);
	}, []);

	const open = useCallback((id: string | null) => {
		if (!id) {
			if (window.history.state?.[PUSHED] && openInUrl()) window.history.back();
			else window.history.replaceState({}, "", urlWith(null));
			setOpenId(null);
			return;
		}
		if (shown.current) window.history.replaceState({ [PUSHED]: window.history.state?.[PUSHED] }, "", urlWith(id));
		else window.history.pushState({ [PUSHED]: true }, "", urlWith(id));
		setOpenId(id);
	}, []);

	return [openId, open] as const;
}

export function EntityOverlay({
	id,
	siblings,
	onOpen,
	onClose,
	onChanged,
}: {
	id: string;
	siblings?: OverlayHost["siblings"];
	onOpen: (id: string, replace?: boolean) => void;
	onClose: () => void;
	onChanged: () => void;
}) {
	const [found, setFound] = useState<{ id: string; lookup: EntityLookup } | null>(null);
	const [error, setError] = useState("");
	const [reloads, setReloads] = useState(0);
	const dialog = useRef<HTMLDivElement>(null);
	const latestOpen = useRef(onOpen);
	latestOpen.current = onOpen;

	useEffect(() => {
		let live = true;
		loadEntityView(id)
			.then((lookup) => {
				if (!live) return;
				setError("");
				if ("renamed" in lookup) latestOpen.current(lookup.renamed, true);
				else setFound({ id, lookup });
			})
			.catch((failure: unknown) => {
				if (live) setError(`Could not load ${id}: ${failure instanceof Error ? failure.message : String(failure)}`);
			});
		return () => {
			live = false;
		};
	}, [id, reloads]);

	useEffect(() => onBoardChange(() => setReloads((count) => count + 1)), []);

	useEffect(() => {
		dialog.current?.focus({ preventScroll: true });
	}, []);

	useEffect(() => {
		dialog.current?.querySelector(".stub")?.scrollTo({ top: 0 });
	}, [found?.id]);

	const lookup = found?.lookup;
	const viewing = lookup && "view" in lookup;

	useKeys((event) => {
		if (viewing || event.key !== "Escape" || typingIn(event.target) || event.defaultPrevented) return;
		event.preventDefault();
		onClose();
	});

	return (
		<div
			className="overlay entity-overlay"
			role="presentation"
			onMouseDown={(event) => event.target === event.currentTarget && onClose()}
		>
			<div
				ref={dialog}
				className={`dialog entity-dialog${found && found.id !== id ? " busy" : ""}`}
				role="dialog"
				aria-modal="true"
				aria-label={`${id} details`}
				aria-busy={!found || found.id !== id}
				tabIndex={-1}
			>
				<header className="dialog-head entity-dialog-head">
					<span className="ident">{id}</span>
					<span className="spacer" />
					<Link
						href={`/card/${id}`}
						className="quiet-link"
						onClick={(event) => {
							if (!confirmDiscard()) event.preventDefault();
						}}
					>
						Open as page
					</Link>
					<button type="button" className="quiet" onClick={onClose} title="Close (Esc)" aria-keyshortcuts="Escape">
						Close
					</button>
				</header>
				{error && (
					<p className="notice error" role="alert">
						<span>{error}</span>
					</p>
				)}
				{!lookup ? (
					!error && <p className="empty entity-loading">Loading {id}…</p>
				) : "view" in lookup ? (
					<EntityView
						data={lookup.view}
						overlay={{
							siblings,
							onOpen,
							onClose,
							onChanged,
							onReload: () => setReloads((count) => count + 1),
						}}
					/>
				) : "archived" in lookup ? (
					<ArchivedEntity entity={lookup.archived} />
				) : (
					<p className="empty entity-loading">{id} is not on the board.</p>
				)}
			</div>
		</div>
	);
}
