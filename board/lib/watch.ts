import { type FSWatcher, watch } from "node:fs";
import path from "node:path";
import { BoardError, boardDirectory, boardRevision } from "./board";

export type Heard = { revision: string } | { error: string };
type Listener = (heard: Heard) => void;

type Watching = {
	listeners: Set<Listener>;
	watchers: FSWatcher[];
	last: Heard | null;
	timer: ReturnType<typeof setTimeout> | null;
	checking: boolean;
	again: boolean;
};

const QUIET = 75;
const RETRY = 2000;
const store = globalThis as typeof globalThis & { cockpitBoardWatch?: Watching };

function watching(): Watching {
	store.cockpitBoardWatch ??= {
		listeners: new Set(),
		watchers: [],
		last: null,
		timer: null,
		checking: false,
		again: false,
	};
	return store.cockpitBoardWatch;
}

function same(one: Heard | null, other: Heard) {
	if (!one) return false;
	if ("revision" in one && "revision" in other) return one.revision === other.revision;
	if ("error" in one && "error" in other) return one.error === other.error;
	return false;
}

async function check() {
	const state = watching();
	if (state.checking) {
		state.again = true;
		return;
	}
	state.checking = true;
	try {
		let heard: Heard;
		try {
			heard = { revision: await boardRevision() };
		} catch (error) {
			heard = { error: error instanceof Error ? error.message : String(error) };
		}
		if (!same(state.last, heard)) {
			state.last = heard;
			for (const listener of state.listeners) listener(heard);
		}
	} finally {
		state.checking = false;
		if (state.again) {
			state.again = false;
			void check();
		}
	}
}

function soon(delay = QUIET) {
	const state = watching();
	if (state.timer) clearTimeout(state.timer);
	state.timer = setTimeout(() => {
		state.timer = null;
		void check();
		if (state.watchers.length === 0 && state.listeners.size > 0) void start();
	}, delay);
}

function stop() {
	const state = watching();
	for (const watcher of state.watchers) watcher.close();
	state.watchers = [];
}

async function start() {
	const state = watching();
	if (state.watchers.length > 0) return;
	let directory: string;
	try {
		directory = await boardDirectory();
	} catch (error) {
		if (!(error instanceof BoardError)) throw error;
		soon(RETRY);
		return;
	}
	if (state.listeners.size === 0 || state.watchers.length > 0) return;
	const git = path.join(directory, ".git");
	const targets: [string, boolean][] = [
		[git, false],
		[path.join(git, "refs"), true],
	];
	try {
		for (const [target, recursive] of targets) {
			const watcher = watch(target, { recursive, persistent: false }, () => soon());
			watcher.on("error", () => {
				stop();
				soon(RETRY);
			});
			state.watchers.push(watcher);
		}
	} catch {
		stop();
		soon(RETRY);
	}
}

export function followBoard(listener: Listener): () => void {
	const state = watching();
	state.listeners.add(listener);
	if (state.last) listener(state.last);
	void start();
	void check();
	return () => {
		state.listeners.delete(listener);
		if (state.listeners.size > 0) return;
		stop();
		state.last = null;
	};
}
