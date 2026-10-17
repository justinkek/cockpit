export type HeldBatch = { batch: string; actions: string[]; ids: string[]; files: number; held: number; due: number };

const RECORD = /^(archive\/)?[a-z]+\/([A-Z][A-Z0-9]*-[0-9]+)[./]/;

export function heldBatches(text: string, delaySeconds: number): HeldBatch[] {
	const batches = new Map<
		string,
		{ actions: Set<string>; ids: Set<string>; paths: Set<string>; first: number; last: number }
	>();
	for (const line of text.split("\n")) {
		const [batch, stamp, action, ...rest] = line.split("\t");
		const file = rest.join("\t");
		if (!batch || !file) continue;
		const seconds = Number(stamp) || 0;
		const entry = batches.get(batch) ?? {
			actions: new Set(),
			ids: new Set(),
			paths: new Set(),
			first: seconds,
			last: seconds,
		};
		if (action) entry.actions.add(action);
		const id = file.match(RECORD)?.[2];
		if (id) entry.ids.add(id);
		entry.paths.add(file);
		entry.first = Math.min(entry.first, seconds);
		entry.last = Math.max(entry.last, seconds);
		batches.set(batch, entry);
	}
	return [...batches].map(([batch, entry]) => ({
		batch,
		actions: [...entry.actions],
		ids: [...entry.ids],
		files: entry.paths.size,
		held: entry.first * 1000,
		due: (entry.last + delaySeconds) * 1000,
	}));
}
