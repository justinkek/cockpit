"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { onBoardChange } from "@/app/live";
import { undoAll } from "@/app/tracked";
import { useWork, type Work } from "@/app/work";
import type { HeldBatch } from "@/lib/held";

const POLL = 1000;
const RECENT = 10000;
const SHOWN_IDS = 6;

const VERBS: Record<string, string> = {
	move: "moved",
	set: "changed",
	create: "created",
	archive: "archived",
	unarchive: "brought back",
	link: "linked",
	unlink: "unlinked",
	undo: "undone",
	comment: "commented on",
	duplicate: "copied",
	section: "changed",
	bounce: "sent back",
	resolve: "resolved",
	reopen: "reopened",
	uncomment: "had a comment removed",
	attach: "given an attachment",
	walk: "walked",
	tracks: "given tracks",
};

function seconds(ms: number) {
	const total = Math.max(0, Math.round(ms / 1000));
	if (total < 60) return `${total}s`;
	return `${Math.floor(total / 60)}m ${String(total % 60).padStart(2, "0")}s`;
}

function idList(ids: string[]) {
	if (ids.length === 0) return null;
	const shown = ids.slice(0, SHOWN_IDS).join(", ");
	return ids.length > SHOWN_IDS ? `${shown} and ${ids.length - SHOWN_IDS} more` : shown;
}

function heldWhat(batch: HeldBatch) {
	const verbs = batch.actions.map((action) => VERBS[action] ?? action).join(" and ");
	const what = idList(batch.ids) ?? `${batch.files} ${batch.files === 1 ? "file" : "files"}`;
	return `${what} ${verbs || "changed"}`;
}

async function fetchHeld(): Promise<{ batches: HeldBatch[]; skew: number } | null> {
	try {
		const response = await fetch("/held", { cache: "no-store" });
		if (!response.ok) return null;
		const answer: { batches?: HeldBatch[]; now?: number } = await response.json();
		return { batches: answer.batches ?? [], skew: (answer.now ?? Date.now()) - Date.now() };
	} catch {
		return null;
	}
}

export function WorkIndicator() {
	const router = useRouter();
	const { running, finished } = useWork();
	const [open, setOpen] = useState(false);
	const [held, setHeld] = useState<HeldBatch[]>([]);
	const [skew, setSkew] = useState(0);
	const [now, setNow] = useState(() => Date.now());
	const [undone, setUndone] = useState<Set<number>>(new Set());
	const box = useRef<HTMLDivElement>(null);
	const lastEnded = finished[0]?.ended ?? 0;

	async function poll() {
		const answer = await fetchHeld();
		if (!answer) return;
		setHeld(answer.batches);
		setSkew(answer.skew);
	}

	useEffect(() => {
		void poll();
		return onBoardChange(() => void poll());
	}, []);

	const wanted = open || running.length > 0 || held.length > 0 || now - lastEnded < RECENT;

	useEffect(() => {
		if (!wanted) return;
		const timer = window.setInterval(() => {
			setNow(Date.now());
			void poll();
		}, POLL);
		setNow(Date.now());
		return () => window.clearInterval(timer);
	}, [wanted]);

	useEffect(() => {
		if (lastEnded) setNow(Date.now());
	}, [lastEnded]);

	useEffect(() => {
		if (!open) return;
		function onKey(event: KeyboardEvent) {
			if (event.key === "Escape") setOpen(false);
		}
		function onPointer(event: PointerEvent) {
			if (!box.current?.contains(event.target as Node)) setOpen(false);
		}
		window.addEventListener("keydown", onKey);
		window.addEventListener("pointerdown", onPointer);
		return () => {
			window.removeEventListener("keydown", onKey);
			window.removeEventListener("pointerdown", onPointer);
		};
	}, [open]);

	const count = running.length + held.length;
	const recent = now - lastEnded < RECENT;
	if (count === 0 && !open && !recent) return null;
	const latest = finished[0];
	const idle = latest && recent ? (latest.failure ? "Failed" : "Done") : "Idle";

	async function undo(work: Work) {
		setUndone((current) => new Set(current).add(work.key));
		await undoAll(work.changes, work.what);
		router.refresh();
	}

	const title =
		count === 0
			? "Nothing is running - click to see what finished"
			: [
					running.length > 0 && `${running.length} ${running.length === 1 ? "change" : "changes"} saving`,
					held.length > 0 && `${held.length} ${held.length === 1 ? "write" : "writes"} waiting to commit`,
				]
					.filter(Boolean)
					.join(", ");

	return (
		<div className="work" ref={box}>
			<button
				type="button"
				className={`work-button${count > 0 ? " busy" : idle === "Failed" ? " failed" : ""}`}
				title={title}
				aria-expanded={open}
				onClick={() => setOpen((shown) => !shown)}
			>
				{count > 0 && <span className="work-spinner" aria-hidden="true" />}
				<span>{count > 0 ? count : idle}</span>
			</button>
			{open && (
				<div className="work-panel" role="dialog" aria-label="Work in the background">
					<section>
						<h3>Running</h3>
						{running.length === 0 ? (
							<p className="work-empty">Nothing from this page is running.</p>
						) : (
							<ul>
								{running.map((work) => (
									<li key={work.key}>
										<span className="work-what">
											<span className="work-spinner" aria-hidden="true" />
											{work.what}
										</span>
										<span className="work-meta">
											{work.total ? `${work.done ?? 0} of ${work.total} · ` : ""}
											{seconds(now - work.started)}
										</span>
										{work.ids.length > 1 && <span className="work-ids">{idList(work.ids)}</span>}
									</li>
								))}
							</ul>
						)}
					</section>
					<section>
						<h3>Waiting to commit</h3>
						{held.length === 0 ? (
							<p className="work-empty">Every write is committed.</p>
						) : (
							<ul>
								{held.map((batch) => {
									const left = batch.due - (now + skew);
									return (
										<li key={batch.batch}>
											<span className="work-what">{heldWhat(batch)}</span>
											<span className="work-meta">{left > 0 ? `commits in ${seconds(left)}` : "committing"}</span>
										</li>
									);
								})}
							</ul>
						)}
					</section>
					{finished.length > 0 && (
						<section>
							<h3>Finished</h3>
							<ul>
								{finished.map((work) => (
									<li key={work.key} className={work.failure ? "failed" : "done"}>
										<span className="work-what">{work.what}</span>
										<span className="work-meta">
											{work.failure ? "Failed" : "Done"} in {seconds((work.ended ?? now) - work.started)}
										</span>
										{work.failure && <span className="work-failure">{work.failure}</span>}
										{!work.failure && work.changes.length > 0 && !undone.has(work.key) && (
											<button type="button" className="quiet work-undo" onClick={() => undo(work)}>
												Undo
											</button>
										)}
									</li>
								))}
							</ul>
						</section>
					)}
				</div>
			)}
		</div>
	);
}
