"use client";

import { useSyncExternalStore } from "react";
import type { Change } from "@/app/actions";

export type Work = {
	key: number;
	what: string;
	ids: string[];
	started: number;
	ended?: number;
	failure?: string;
	changes: Change[];
};

export type Outcome = { failure?: string; changes?: Change[] };

const KEPT = 5;

let made = 0;
let snapshot: { running: Work[]; finished: Work[]; busy: Set<string> } = {
	running: [],
	finished: [],
	busy: new Set(),
};
const listeners = new Set<() => void>();

function publish(running: Work[], finished: Work[]) {
	snapshot = { running, finished, busy: new Set(running.flatMap((work) => work.ids)) };
	for (const listener of listeners) listener();
}

function subscribe(listener: () => void) {
	listeners.add(listener);
	return () => listeners.delete(listener);
}

function current() {
	return snapshot;
}

const EMPTY = { running: [], finished: [], busy: new Set<string>() };

function server() {
	return EMPTY;
}

export function onWorkChange(listener: () => void) {
	return subscribe(listener);
}

export function workRunning() {
	return snapshot.running.length;
}

export function useWork() {
	return useSyncExternalStore(subscribe, current, server);
}

export function useBusyIds(): Set<string> {
	return useWork().busy;
}

export function useBusy(id: string): boolean {
	return useWork().busy.has(id);
}

export function busyWith(ids: string[]): string | null {
	return ids.find((id) => snapshot.busy.has(id)) ?? null;
}

export function stillSaving(id: string) {
	return `${id} is still saving`;
}

export function withBusy(pending: Set<string>, busy: Set<string>): Set<string> {
	if (busy.size === 0) return pending;
	if (pending.size === 0) return busy;
	return new Set([...pending, ...busy]);
}

function end(key: number, outcome: Outcome) {
	const work = snapshot.running.find((one) => one.key === key);
	if (!work) return;
	const ended: Work = {
		...work,
		ended: Date.now(),
		failure: outcome.failure,
		changes: outcome.changes ?? [],
	};
	publish(
		snapshot.running.filter((one) => one.key !== key),
		[ended, ...snapshot.finished].slice(0, KEPT),
	);
}

export async function track<T>(
	what: string,
	ids: string[],
	task: () => Promise<T>,
	outcome: (result: T) => Outcome,
): Promise<T> {
	made += 1;
	const key = made;
	publish(
		[...snapshot.running, { key, what, ids: [...new Set(ids)], started: Date.now(), changes: [] }],
		snapshot.finished,
	);
	try {
		const result = await task();
		end(key, outcome(result));
		return result;
	} catch (error) {
		end(key, { failure: error instanceof Error ? error.message : String(error) });
		throw error;
	}
}
