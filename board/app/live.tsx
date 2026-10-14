"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";

const CHANGED = "cockpit-board-change";
const EVERY = 3000;

type State = { tone: "live" | "paused" | "offline"; detail: string };

export function onBoardChange(listener: (revision: string) => void) {
	function heard(event: Event) {
		listener((event as CustomEvent<string>).detail);
	}
	window.addEventListener(CHANGED, heard);
	return () => window.removeEventListener(CHANGED, heard);
}

function shown() {
	return document.visibilityState !== "hidden";
}

async function fetchRevision(): Promise<string> {
	const response = await fetch("/revision", { cache: "no-store" });
	const answer: { revision?: string; error?: string } = await response.json().catch(() => ({}));
	if (!response.ok || !answer.revision) throw new Error(answer.error ?? `the board answered ${response.status}`);
	return answer.revision;
}

export function LiveUpdates() {
	const router = useRouter();
	const [state, setState] = useState<State>({ tone: "live", detail: "" });
	const known = useRef<string | null>(null);
	const checkNow = useRef<() => void>(() => {});

	useEffect(() => {
		let timer = 0;
		let running = false;
		let stopped = false;

		async function check() {
			window.clearTimeout(timer);
			if (stopped) return;
			if (!shown()) {
				setState({ tone: "paused", detail: "" });
				return;
			}
			if (running) return;
			running = true;
			try {
				const revision = await fetchRevision();
				const before = known.current;
				known.current = revision;
				setState({ tone: "live", detail: "" });
				if (before !== null && before !== revision) {
					router.refresh();
					window.dispatchEvent(new CustomEvent(CHANGED, { detail: revision }));
				}
			} catch (error) {
				setState({ tone: "offline", detail: error instanceof Error ? error.message : String(error) });
			} finally {
				running = false;
				if (!stopped && shown()) timer = window.setTimeout(check, EVERY);
			}
		}

		checkNow.current = check;
		check();
		document.addEventListener("visibilitychange", check);
		window.addEventListener("focus", check);
		window.addEventListener("online", check);
		return () => {
			stopped = true;
			window.clearTimeout(timer);
			document.removeEventListener("visibilitychange", check);
			window.removeEventListener("focus", check);
			window.removeEventListener("online", check);
		};
	}, [router]);

	const label = state.tone === "offline" ? "Offline" : state.tone === "paused" ? "Paused" : "Live";
	const title =
		state.tone === "offline"
			? `Not following the board: ${state.detail} - click to try again`
			: state.tone === "paused"
				? "Paused while this tab is hidden"
				: "Changes made anywhere on the board show here within a few seconds";
	return (
		<button
			type="button"
			className={`live ${state.tone}`}
			title={title}
			onClick={() => checkNow.current()}
		>
			<span className="live-dot" aria-hidden="true" />
			<span className="live-label">{label}</span>
		</button>
	);
}
