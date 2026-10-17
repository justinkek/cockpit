"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { onWorkChange, workRunning } from "@/app/work";

const CHANGED = "cockpit-board-change";
const FALLBACK = 60000;
const RECONNECT = 2000;
const SETTLE = 250;

type State = { tone: "live" | "paused" | "offline"; detail: string };

export function onBoardChange(listener: (revision: string) => void) {
	function heard(event: Event) {
		listener((event as CustomEvent<string>).detail);
	}
	window.addEventListener(CHANGED, heard);
	return () => window.removeEventListener(CHANGED, heard);
}

let pending = 0;
const settled = new Set<() => void>();

function isAction(input: RequestInfo | URL, init?: RequestInit) {
	const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
	return headers.has("next-action");
}

function watchActions() {
	if (typeof window === "undefined") return;
	const marked = window as typeof window & { cockpitActionsWatched?: boolean };
	if (marked.cockpitActionsWatched) return;
	marked.cockpitActionsWatched = true;
	const original = window.fetch.bind(window);
	window.fetch = async (input, init) => {
		if (!isAction(input, init)) return original(input, init);
		pending++;
		let done = false;
		function finish() {
			if (done) return;
			done = true;
			pending--;
			if (pending === 0) for (const listener of settled) listener();
		}
		try {
			const response = await original(input, init);
			const copy = response.clone();
			void copy
				.arrayBuffer()
				.catch(() => {})
				.finally(finish);
			return response;
		} catch (error) {
			finish();
			throw error;
		}
	};
}

watchActions();

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
		let owed: string | null = null;
		let settle = 0;

		function refresh() {
			window.clearTimeout(settle);
			if (owed === null || pending > 0 || workRunning() > 0) return;
			const revision = owed;
			owed = null;
			router.refresh();
			window.dispatchEvent(new CustomEvent(CHANGED, { detail: revision }));
		}

		function quiet() {
			window.clearTimeout(settle);
			settle = window.setTimeout(refresh, SETTLE);
		}

		function heard(revision: string) {
			const before = known.current;
			known.current = revision;
			if (before === null || before === revision) return;
			owed = revision;
			if (pending === 0 && workRunning() === 0) refresh();
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
		function workChanged() {
			if (workRunning() === 0 && pending === 0 && owed !== null) quiet();
		}

		settled.add(quiet);
		const unwatch = onWorkChange(workChanged);
		connect();
		poll = window.setTimeout(fallback, FALLBACK);
		document.addEventListener("visibilitychange", visibility);
		window.addEventListener("online", online);
		window.addEventListener("focus", online);
		return () => {
			stopped = true;
			settled.delete(quiet);
			unwatch();
			window.clearTimeout(settle);
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
