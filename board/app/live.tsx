"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";

const CHANGED = "cockpit-board-change";
const FALLBACK = 60000;
const RECONNECT = 2000;

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
	const reconnectNow = useRef<() => void>(() => {});

	useEffect(() => {
		let source: EventSource | null = null;
		let retry = 0;
		let poll = 0;
		let stopped = false;

		function heard(revision: string) {
			const before = known.current;
			known.current = revision;
			if (before === null || before === revision) return;
			router.refresh();
			window.dispatchEvent(new CustomEvent(CHANGED, { detail: revision }));
		}

		function close() {
			window.clearTimeout(retry);
			source?.close();
			source = null;
		}

		function connect() {
			close();
			if (stopped) return;
			if (!shown()) {
				setState({ tone: "paused", detail: "" });
				return;
			}
			const opened = new EventSource("/events");
			source = opened;
			opened.onopen = () => setState({ tone: "live", detail: "" });
			opened.onmessage = (event) => {
				setState({ tone: "live", detail: "" });
				heard(event.data);
			};
			opened.addEventListener("failure", (event) => {
				setState({ tone: "offline", detail: (event as MessageEvent<string>).data });
			});
			opened.onerror = () => {
				if (source !== opened) return;
				setState({ tone: "offline", detail: "the connection to the board app dropped" });
				if (opened.readyState === EventSource.CLOSED) {
					source = null;
					retry = window.setTimeout(connect, RECONNECT);
				}
			};
		}

		async function fallback() {
			window.clearTimeout(poll);
			if (stopped) return;
			if (shown()) {
				try {
					heard(await fetchRevision());
				} catch {}
			}
			poll = window.setTimeout(fallback, FALLBACK);
		}

		function visibility() {
			if (shown()) connect();
			else {
				close();
				setState({ tone: "paused", detail: "" });
			}
		}

		function online() {
			if (!source) connect();
		}

		reconnectNow.current = () => {
			connect();
			void fallback();
		};
		connect();
		poll = window.setTimeout(fallback, FALLBACK);
		document.addEventListener("visibilitychange", visibility);
		window.addEventListener("online", online);
		window.addEventListener("focus", online);
		return () => {
			stopped = true;
			close();
			window.clearTimeout(poll);
			document.removeEventListener("visibilitychange", visibility);
			window.removeEventListener("online", online);
			window.removeEventListener("focus", online);
		};
	}, [router]);

	const label = state.tone === "offline" ? "Offline" : state.tone === "paused" ? "Paused" : "Live";
	const title =
		state.tone === "offline"
			? `Not following the board: ${state.detail} - click to try again`
			: state.tone === "paused"
				? "Paused while this tab is hidden"
				: "Changes made anywhere on the board show here as they happen";
	return (
		<button type="button" className={`live ${state.tone}`} title={title} onClick={() => reconnectNow.current()}>
			<span className="live-dot" aria-hidden="true" />
			<span className="live-label">{label}</span>
		</button>
	);
}
